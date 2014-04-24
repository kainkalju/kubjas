#!/usr/bin/perl

use Config;

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

while (1) { sleep 1; }
