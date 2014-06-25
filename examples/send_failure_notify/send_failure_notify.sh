#!/bin/sh

SENDTO='admin@example.dom 1234567890@paging.dom'

SMTP_HOST=smtp.relay.dom
FROM_ADDR=kubjas@examle.dom

if [ $# -lt 3 ]; then
	echo "Usage: $0 %host% %job% %notify%"
	exit 1;
fi

DATE=`date +'%F %X'`

# using ssmtp. see man sendmail
SENDMAIL=/usr/lib/sendmail

# temporary config
CONF=/tmp/smtp.conf.$$
echo "root=postmaster" > $CONF
echo "mailhub=$SMTP_HOST" >> $CONF
echo "hostname=hostname.example.dom" >> $CONF

# temporary message file
MSGFILE=/tmp/send_failure_notify.msg.$$

for to in $SENDTO
do
	echo "To: $to" > $MSGFILE
	echo "Subject: Failure notify $DATE" >> $MSGFILE
	echo "X-Mailer: send_failure_notify" >> $MSGFILE
	echo "" >> $MSGFILE
	echo "Kubjas failure notify: $1 [$2] $3 - $DATE" >> $MSGFILE
	$SENDMAIL -C$CONF -f$FROM_ADDR $to < $MSGFILE
done

# clean
rm -f $CONF
rm -f $MSGFILE
