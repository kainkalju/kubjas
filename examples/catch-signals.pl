#!/usr/bin/perl

use POSIX 'setsid';
use Config;

#&daemonize;

defined($Config{sig_name})  || die "No sigs?";
foreach my $name (split(" ", $Config{sig_name})) {
        $signo{$name} = $i;
        $i++;
}

while (my($sig,$n) = each %signo) {
	$SIG{$sig} = sub { print "$0 : Got signal $sig\n"; };
}
$SIG{INT} = sub { print "$0 : Got signal INT\n"; exit; };
$SIG{TERM} = sub { print "$0 : Got signal TERM\n"; exit; };

#while (1) { }
while (1) { sleep 1; last if (++$x>=100); }

# daemonize

sub daemonize {
  chdir '/' or die "Can't chdir to /: $!";
  open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
  defined($pid = fork) or die "Can't fork: $!";
  exit if $pid;
  setsid or die "Can't start a new session: $!";
  open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
}

