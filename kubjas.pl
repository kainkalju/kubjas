#!/usr/bin/perl
#
# kubjas  Ver 140424
#
# Script was written by Kain Kalju (kain@kalju.com)
# (c) 2014 FlyCom OY (reg.code 10590327)
# Ehitajate tee 108, Tallinn, Estonia
# +372 680 6122
# http://www.flycom.ee/

use POSIX qw/:sys_wait_h setsid/;
use IO::Select;
use IO::Socket;
use Config::IniFiles;
use Linux::Inotify2;
use Time::Period;
use Time::HiRes qw(ualarm gettimeofday);
use Config;
use strict;
use vars qw($start_time $last_time @jobs %signo %running %started %childs %stop_notify %inwatch %stms);

my $default_cfg = '/etc/kubjas.conf';
my $config_dir = '/etc/kubjas.d';

printf "%s  Starting [kubjas] PID %d at host \"%s\"\n", scalar(localtime), $$, &whoami;

our $inotify = new Linux::Inotify2
    or die "Unable to create new inotify object: $!" ;
$inotify->blocking(0); # nonblocking

$start_time = time();
&reading_conf;

## REGISTER SIGNAL HANDLING ##

$SIG{CHLD} = sub {
	while( ( my $child = waitpid( -1, &WNOHANG ) ) > 0 ) {
		my $name = $childs{$child};
		if ($name) {
			printf "%s  PID %d exited [%s] running time %s.\n", scalar(localtime), $child, $name, &elapsed_time($started{$name},$stms{$name});
			delete $running{$name};
			delete $childs{$child};
			if ($stop_notify{$name}) {
				for (split(/\n/,$stop_notify{$name})) {
					&send_notify($_, $name, 'stop-message');
				}
			}
		}
	}
};
$SIG{HUP} = \&reading_conf;
$SIG{TERM} = \&shutdown;
$SIG{INT} = \&shutdown;
$SIG{USR1} = sub { printf "%s  running (%s)\n", scalar(localtime), join(" ", keys %running); };

## REGISTER SIGNAL NAMES ##

defined($Config{sig_name})  || die "No sigs?";
my $i = 0;
foreach my $name (split(" ", $Config{sig_name})) {
	$signo{$name} = $i;
	$i++;
}

## START LISTEN NETWORK ##

my $sock = IO::Socket::INET->new( LocalPort => 2380, Proto => 'udp' )
   or die "Couldn't be a udp server on port 2380 : $@\n";
my $sel = IO::Select->new( $sock );
my $packet;

## EVENT LOOP ##

$SIG{ALRM} = sub { &start_jobs('time'); ualarm(100_000); };
ualarm(100_000);

while (1) {
	for ($inotify->read) {
		ualarm(0);
		&start_jobs('watch', $_->fullname, $_->mask);
		ualarm(100_000);
	}
	foreach my $fh ($sel->can_read) {
		ualarm(0);
		my $him = $fh->recv($packet, 4096, 0);
		my @notify = &recv_notify($him,$packet);
		if (scalar(@notify)) {
			send($fh, "OK\n", 0, $him);
			&start_jobs('notify', @notify);
		}
		ualarm(100_000);
	}
}

## PARSING NOTIFY MESSAGE ##

sub recv_notify {
	my $him = shift;
	my $packet = shift;
	chomp $packet;
	my ($port, $iaddr) = sockaddr_in($him);
	my $remote = inet_ntoa($iaddr);
	print scalar(localtime), "  notify from $remote:$port {$packet}\n";
	my ($remote_host, $to_job, $from_job, $notify) = split(/\s/,$packet,4);
	my $valid_message = 0;
	for (qw(start-message stop-message ping)) {
		if ($notify eq $_) {
			$valid_message = 1;
		}
	}
	return unless ($valid_message);
	my @msg = ($to_job, $notify, $from_job, $remote_host);
	return @msg;
}

## SEND NOTIFY MESSAGE ##

sub send_notify {
	my ($remote,$myjob,$notify) = @_;

	my $pid;
	defined($pid = fork) or die "Can't fork: $!";
	return $pid if ($pid);
	ualarm(0);

	my ($remote_host, $remote_job) = split(/:/,$remote);
	my $myhost = &whoami;
	my $message = "$myhost $remote_job $myjob $notify";

	my $sock = IO::Socket::INET->new(PeerAddr => "$remote_host:2380", Proto => 'udp');
	$sock->send($message);

	my $i = 0;
	my $rec;
	while (!$rec) {
		local $SIG{ALRM} = sub { $sock->send($message); alarm 1; };
		alarm 1;
		$sock->recv($rec,1024);
		alarm 0;
		last if (++$i >= 3);
	}
	unless (substr($rec,0,2) eq 'OK') {
		print "WARN: $remote_host did not respond to notify!\n";
	}
	exit;
}

## STOP DAEMON JOBS ##

sub stop_daemon_jobs {
	foreach my $job (@jobs) {
		my $name = $job->get_param('name');

		if ($running{$name} && $job->get_param('run') eq 'daemon') {
			kill $signo{'TERM'}, $running{$name};
		}
	}
}

## START JOBS ##

sub start_jobs {
	my ($trigger,@msg) = @_;
	my ($time,$watch,$notify);
	if ($trigger eq 'time') { $time = time; }
	elsif ($trigger eq 'notify') { $notify = shift @msg; }
	elsif ($trigger eq 'watch') { $watch = shift @msg; }

	return if ($time && ($time - $last_time) < 1); # once in a sec.
	$last_time = $time;

	foreach my $job (@jobs) {
		my $name = $job->get_param('name');

		next if ($notify && $notify ne $name);
		next unless (inPeriod(time(), $job->get_param('period')));
		next if (inConflicts($job));
		next if (noDepency($job));

		my $interval = $job->get_param('interval');
		next unless ($interval);
		next if ($watch && lc($interval) ne 'onchange');
		next if (!$watch && lc($interval) eq 'onchange');
		next if ($notify && lc($interval) ne $msg[0]);
		next if (!$watch && !$notify && $interval !~ /\d/ && $job->get_param('run') ne 'daemon');
		next if ($time && $interval =~ /\d/ && ($time - $started{$name}) < $interval);
		next if ($time && $interval =~ /\d/ && ($time - $start_time) < $interval);

		my $signal = $job->get_param('signal');
		if ($signal && $notify && $running{$name}) {
			if ($signal =~ /^\d+$/) {
				kill $signal, $running{$name};
			} else {
				kill $signo{$signal}, $running{$name};
			}
		}
		unless ($running{$name}) {
			my $pid = &exec_job(
				$job->get_param('cmdline'),
				$job->get_param('user'),
				$job->get_param('run')
			);
			if ($pid) {
				print scalar(localtime), "  EXEC [$name] PID $pid\n";
				$childs{$pid} = $name;
				$running{$name} = $pid;
				for (split(/\n/,$job->get_param('notify'))) {
					&send_notify($_, $name, 'start-message');
				}
				$stop_notify{$name} = $job->get_param('notify');
			} else {
				print scalar(localtime), "  FAILED EXEC $name\n";
			}
			($started{$name}, $stms{$name}) = gettimeofday;
		}

	}
}

sub inConflicts {
	my $job = shift;
	my $conflict = 0;
	for (split(/\n/,$job->get_param('conflicts'))) {
		if ($running{$_}) {
			$conflict = 1;
			last;
		}
	}
	return $conflict;
}

sub noDepency {
	my $job = shift;
	my $dependecy = 0;
	for (split(/\n/,$job->get_param('depends'))) {
		unless ($running{$_}) {
			$dependecy = 1;
			last;
		}
	}
	return $dependecy;
}

sub whoami {
	my $hostname;
	open FILE, "/proc/sys/kernel/hostname";
	read FILE, $hostname, 1024;
	close FILE;
	unless ($hostname) {
		open PROG, "/bin/hostname |";
		read PROG, $hostname, 1024;
		close PROG;
	}
	chomp $hostname;
	return $hostname;
}

sub shutdown {
	print scalar(localtime), "  Shutdown\n";
	&stop_daemon_jobs;
	exit;
}

sub elapsed_time {
	my $time = shift;
	my $microseconds = shift;
	my ($s, $ms) = gettimeofday;
	$time = $s - $time;
	$microseconds = $ms - $microseconds;
	my ($days,$hours,$minutes,$seconds);
	my $day = 86400;
	my $hour = 3600;
	my $min = 60;

	while ($time >= $day) { ++$days; $time -= $day; }
	while ($time >= $hour) { ++$hours; $time -= $hour; }
	while ($time >= $min) { ++$minutes; $time -= $min; }
	$seconds = $time;

	my $ret;
	$ret .= "${days}d " if ($days);
	$ret .= "${hours}h " if ($hours);
	$ret .= "${minutes}m " if ($minutes);
	$ret .= "${seconds}s" if ($seconds);
	$ret .= sprintf "%.3fs", $microseconds/1000000 unless ($time);
	return $ret;
}

## FIND ALL CONFIGURATION FILES ##

sub reading_conf {

print scalar(localtime), "  reading_conf\n";

my @cfg_files = ( $default_cfg );

opendir(DIR, $config_dir) || die "can't opendir $config_dir: $!";
my @files = grep { !/^\./ && -f "$config_dir/$_" } readdir(DIR);
closedir DIR;

for (@files) {
	next if (/dpkg-old$/); # ignore old deb files
	next if (/~$/); # ignore nano backup files
	next if (! -r "$config_dir/$_" ); # ignore files we cannot read
	push @cfg_files, "$config_dir/$_";
}

my %uniq;
@jobs = ();

for (@cfg_files) {
	my $cfg = Config::IniFiles->new(
		-file => $_,
		-nocase => 1,
		-allowempty => 1,
	);
	for ($cfg->Sections) {
		if ($uniq{$_}) {
			my $cfg_filename = $cfg->GetFileName;
			warn "warn: duplicate job [$_] in $cfg_filename\n";
			next;
		}
		$uniq{$_}=1;

		my $job = Kubjas::Job->new( name => $_ );
		my $sec = $_;

		foreach my $key ($job->get_param_names) {
			next if ($key eq 'name'); # do not overwrite job name
			my $val = $cfg->val($sec, $key);
			$job->set_param($key, $val) if ($val);
		}
		if (! -x $job->get_param('cmdline') ) {
			printf "cannot execute [%s] %s\n", $job->get_param('name'), $job->get_param('cmdline');
		} else {
			push @jobs, $job;
		}
	}
}

foreach my $job (@jobs) {
	my $w = $job->get_param('watch');
	for (split(/\n/,$w)) {
		unless ($inwatch{$_}) {
			# create watch
			$inotify->watch ($_, IN_CLOSE_WRITE)
			   or die "$_ watch creation failed";
			$inwatch{$_}=1;
		}
	}
}

return @jobs;
}

## EXEC JOBS ##

sub exec_job {
	my $cmdline = shift;
	my $user = shift;
	my $daemon = shift;
	unless ($user) { $user = 'root'; }
	my $uid = getpwnam($user);
	if (!$uid && $user ne 'root') {
		print "cannot find user $user\n";
		return;
	}
	my $gid = getgrnam($user);
	my $pid;
	defined($pid = fork) or die "Can't fork: $!";
	return $pid if ($pid);
	chdir '/' or die "Can't chdir to /: $!";
	open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
	if ($daemon eq 'daemon') {
		open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
	}
	setsid or die "Can't start a new session: $!";
	open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
	$<=$>=$uid;
	$(=$)=$gid;
	{ exec ($cmdline) }; print STDERR "couldn't exec $cmdline: $!";
}

## JOB OBJECT ##

package Kubjas::Job;

sub new {
	my $class = shift;
	my %parms = @_;

	my $self = bless {
		'name' => undef,
		'cmdline' => undef,
		'user' => 'root', # start job with user permissions
		'interval' => 0, # seconds | onchange | start-message | stop-message
		'period' => 'mo {1-12}', # man Time::Period
		'conflicts' => undef, # other job names \n separated array
		'depends' => undef, # other job names \n separated array
		'run' => 'periodic', # or 'daemon'
		'watch' => undef, # file or direcotry list for inotify
		'notify' => undef, # other-server:job-name | local-job-name
		'signal' => undef, # notify signal: HUP, INT, USR2, ...
	}, $class;

	while (my($k,$v) = each %parms) {
		$self->{$k} = $v;
	}
	return $self;
}

sub get_param_names {
	my $self = shift;
	return keys %{ $self };
}

sub get_param {
	my $self = shift;
	my $key = shift;
	return $self->{$key};
}

sub set_param {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	$self->{$key} = $val;
}

1;
