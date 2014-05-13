#!/usr/bin/perl

use Mail::Sendmail;

my @sendto = ('admin@example.dom','1234567890@paging.dom');

my $smtp_host = 'smtp.relay.dom';
my $from_addr = 'kubjas@examle.dom';

unless ($ARGV[2]) {
	print "Usage: $0 %host% %job% %notify%\n";
	exit 1;
}

## send message

for (@sendto) {
  my $to = $_;
  my $message = &print_message (@ARGV);
  my $subj = 'Failure notify '.&make_date(time);
  my %mail = (
        To      => $to,
        From    => $from_addr,
        'Subject' => $subj,
        'X-Mailer' => 'send_failure_notify',
        Smtp    => $smtp_host,
        Message => $message,
  );
  sendmail(%mail) or die $Mail::Sendmail::error;
}

sub print_message {
 my ($remote_host,$from_job,$notify_msg) = @_;
 my $datestamp = &make_date(time);
 my $message = <<EOF;
Kubjas failure notify: $remote_host [$from_job] $notify_msg - $datestamp
EOF
 return $message;
}

sub make_date {
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_[0]);
  return sprintf ("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
}

