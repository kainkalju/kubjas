#!/usr/bin/perl
#
# kubjas  Ver 140427
#
# Script was written by Kain Kalju (kain@kalju.com)
# (c) 2014 FlyCom OY (reg.code 10590327)
# Ehitajate tee 108, Tallinn, Estonia
# +372 680 6122
# http://www.flycom.ee/

use POSIX qw/:sys_wait_h setsid/;
use IO::Select;
use IO::Socket;
use Compress::Zlib qw(crc32);
use Config::IniFiles;
use Linux::Inotify2;
use Time::Period;
use Time::HiRes qw(ualarm gettimeofday);
use Config;
use strict;
use vars qw($start_time $last_time @jobs %signo %running %started %childs %inwatch %stms %known @fp_lifo);

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
	while( ( my $pid = waitpid( -1, &WNOHANG ) ) > 0 ) {
		my $status = $?;
		my $exit = $? >> 8;
		my $signal = $? & 127;
		my $job = $childs{$pid};
		if ($job) {
			my $name = $job->get_param('name');
			if ($exit > 0) {
				printf "%s  PID %d exited [%s] running time %s.\n", scalar(localtime), $pid, $name, &elapsed_time($started{$name},$stms{$name});
				print scalar(localtime), "  FAILURE: PID $pid exited with status = $status (exit=$exit, signal=$signal)\n";
				my $notify = $job->get_param('notify-failure');
				for (split(/\n/,$notify)) {
					&send_notify($_, $name, 'failure-message');
				}
			} else {
				printf "%s  PID %d exited [%s] running time %s.\n", scalar(localtime), $pid, $name, &elapsed_time($started{$name},$stms{$name});
				my $notify = $job->get_param('notify-success');
				for (split(/\n/,$notify)) {
					&send_notify($_, $name, 'success-message');
				}
			}
			delete $running{$name};
			delete $childs{$pid};
		}
		elsif ($exit > 0) {
			print scalar(localtime), "  WARN: PID $pid exited with status = $status (exit=$exit, signal=$signal)\n";
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

$SIG{ALRM} = sub { &start_jobs('time'); ualarm(200_000); };
ualarm(200_000);

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
	return if (&duplicate_filter($packet));
	print scalar(localtime), "  notify from $remote:$port {$packet}\n";
	my ($remote_host, $to_job, $from_job, $notify, $timest) = split(/\s/,$packet,5);
	my $valid_message = 0;
	for (qw(start-message success-message failure-message ping)) {
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
	my $timest = time();
	my $message = "$myhost $remote_job $myjob $notify $timest";

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

## NOTIFY MESSAGES DUPLICATE FILTER ##

sub duplicate_filter {
	my $msg = shift;
	my $fingerprint = crc32($msg);

	return 1 if ($known{$fingerprint} && $msg eq $known{$fingerprint});
	
	$known{$fingerprint} = $msg;
	push @fp_lifo, $fingerprint;
	if (scalar(@fp_lifo) > 20) { # keep only last 20
		my $fingerprint = shift @fp_lifo;
		delete $known{$fingerprint};
	}
	return 0;
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
	my $sort_jobs = 0;

	foreach my $job (@jobs) {
		my $name = $job->get_param('name');
		my $daemon = $job->get_param('run') eq 'daemon' ? 'daemon' : 0;

		next if ($notify && $notify ne $name);
		next unless (inPeriod(time(), $job->get_param('period')));
		next if (inConflicts($job));
		next if (noDepency($job));

		my $interval = $job->get_param('interval');
		next unless ($interval);
		if ($interval =~ m,(\d+)\s*-\s*(\d+),) { # randomized range intervals
			my $diff = abs( $2 - $1 );
			$interval = int(rand($diff)) + $1;
		}
		next if ($watch && lc($interval) ne 'onchange');
		next if (!$watch && lc($interval) eq 'onchange' && !$daemon);
		next if ($notify && lc($interval) ne $msg[0]);
		next if (!$watch && !$notify && $interval !~ /\d/ && !$daemon);
		next if ($time && $interval =~ /\d/ && ($time - $started{$name}) < $interval);
		next if ($time && $interval =~ /\d/ && ($time - $start_time) < $interval);

		my $signal = $job->get_param('signal');
		if ($signal && ($notify || $watch) && $running{$name}) {
			if ($signal =~ /^\d+$/) {
				kill $signal, $running{$name};
			} else {
				kill $signo{$signal}, $running{$name};
			}
		}
		unless ($running{$name}) {
			my $pid = &exec_job($job);
			if ($pid) {
				print scalar(localtime), "  EXEC [$name] PID $pid\n";
				$childs{$pid} = $job;
				$running{$name} = $pid;
				for (split(/\n/,$job->get_param('notify-start'))) {
					&send_notify($_, $name, 'start-message');
				}
			} else {
				print scalar(localtime), "  FAILED EXEC $name\n";
			}
			($started{$name}, $stms{$name}) = gettimeofday;
			$job->set_param('exec_time', time);
			$sort_jobs = 1;
		}
	}
	if ($sort_jobs) {
		my @tmpjobs;
		foreach my $job (sort { $a->{'exec_time'} <=> $b->{'exec_time'} } @jobs) {
			push @tmpjobs, $job;
		}
		@jobs = @tmpjobs;
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

sub isExecutable {
	my $cmdline = shift;
	return unless ($cmdline);
	my $cmd = $cmdline;

	if ($cmdline =~ /\s/) {
		($cmd) = split(/\s/,$cmdline);
	}
	if ( -x $cmd ) {
		return 1;
	}
	for (split(/:/, $ENV{'PATH'})) {
		if ( -x "$_/$cmd" ) {
			return 1;
		}
	}
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
	$ret .= sprintf "%.3fs ", $microseconds/1000000 unless ($ret);
	$ret =~ s/\s$//g; # remove trailing space
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
	my $any = join("\n", $cfg->Sections);
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
			if ($key eq 'depends' && $val eq '*') { $val = $any; }
			if ($key eq 'conflicts' && $val eq '*') { $val = $any; }
			$job->set_param($key, $val) if ($val);
		}
		if (inPeriod(time(), $job->get_param('period')) < 0) {
			printf "incorrect period [%s] %s\n", $job->get_param('name'), $job->get_param('period');
			next;
		}
		unless (&isExecutable($job->get_param('cmdline'))) {
			printf "cannot execute [%s] %s\n", $job->get_param('name'), $job->get_param('cmdline');
			next;
		}
		push @jobs, $job;
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
	my $job = shift;
	my $cmdline = $job->get_param('cmdline');
	my $run = $job->get_param('run');
	my $user = $job->get_param('user');
	my $group = $job->get_param('group');
	my $ionice = $job->get_param('ionice');
	my $nice = $job->get_param('nice');
	if ($ionice && ! -x '/usr/bin/ionice') {
		print "WARN: cannot find /usr/bin/ionice\n";
		$ionice = undef;
	}
	if ($nice && ! -x '/usr/bin/renice') {
		print "WARN: cannot find /usr/bin/renice\n";
		$nice = undef;
	}
	unless ($user) { $user = 'root'; }
	my $uid = getpwnam($user);
	if (!$uid && $user ne 'root') {
		print "exec_job: cannot find user $user\n";
		return;
	}
	unless ($group) { $group = $user; }
	my $gid = getgrnam($group);
	my $pid;
	defined($pid = fork) or die "Can't fork: $!";
	return $pid if ($pid);
	system ("/usr/bin/ionice -c 3 -p $$") if ($ionice);
	system ("/usr/bin/renice +10 $$ >/dev/null") if ($nice);
	chdir '/' or die "Can't chdir to /: $!";
	open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
	if ($run eq 'daemon') {
		open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
	}
	setsid or die "Can't start a new session: $!";
	open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
	$(=$)=$gid;
	$<=$>=$uid;
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
		'group' => 'root', # start job with group permissions
		'interval' => 0, # seconds | onchange | start-message | success-message | failure-message
		'period' => 'mo {1-12}', # man Time::Period
		'conflicts' => undef, # other job names \n separated array
		'depends' => undef, # other job names \n separated array
		'run' => 'periodic', # or 'daemon'
		'watch' => undef, # file or direcotry list for inotify
		'notify-start' => undef, # other-server:job-name | local-job-name
		'notify-success' => undef, # other-server:job-name | local-job-name
		'notify-failure' => undef, # other-server:job-name | local-job-name
		'signal' => undef, # notify signal: HUP, INT, USR2, ...
		'ionice' => 0, # 0 - false, 1 - true
		'nice' => 0, # 0 - false, 1 - true
		'exec_time' => 0,
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
