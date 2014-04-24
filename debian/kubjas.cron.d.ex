#
# Regular cron jobs for the kubjas package
#
0 4	* * *	root	[ -x /usr/bin/kubjas_maintenance ] && /usr/bin/kubjas_maintenance
