kubjas
======

NAME
    kubjas - (cron like) daemon to execute scheduled commands

SYNOPSIS
    kubjas.pl [--background] [--conf_file /etc/kubjas.conf] [--log_file
    /path/kubjas.log] [--pid_file /path/kubjas.pid]

DESCRIPTION
    Kubjas is periodic job scheduler that operates with minimum 1 second
    intervals.

    Kubjas is not another cron daemon. Kubjas does not start programs at
    certain time but at specified intervals. Kubjas also includes
    Time::Period filter. You can configure interval and period combinations
    that act like crontab.

    Kubjas measures executed job running times and log it when job exits.
    Measurements are in microseconds resolution.

    Kubjas configuration is standard INI file format. You can have multiple
    configuration files at same time. Main configuration is /etc/kubjas.conf
    and /etc/kubjas.d/ directory is for additional configurations. Each job
    can have her own config file. You can force configuration reload with
    HUP signal.

CONFIGURATION
    example.conf
         [*]
         notify-failure = 192.168.1.27:catch-signals

         [date-job]
         cmdline = date +"%H:%M" > /var/tmp/date.txt
         interval = 60
         user = nobody
         group = nogroup
         notify-success = 192.168.1.27:catch-signals

         [catch-signals]
         cmdline = /usr/local/bin/catch-signals.pl
         output = none
         interval = failure-message
         signal = USR2

         [readfile]
         cmdline = /usr/local/bin/readfile.sh
         interval = onchange
         watch = /var/tmp/date.txt
         output = /tmp/date.log
         user = nobody
         group = nogroup

         [very-shy-job]
         cmdline = /usr/local/bin/shy.sh
         interval = 10-20
         period = wd {1 3 5 7} min {0-29}, wd {2 4 6} min {30-59}
         depends = catch-signals
         conflicts = date-job
         nice = 1
         ionice = 1

    job-name
        [job-name] is the INI file section. Job names must be unique.

        Special section name [*] sets default params that will be used with
        all jobs defined at the same configuration file. Named job sections
        overwrite default params.

    cmdline
        Parameter cmdline define executable program with parameters

         cmdline = perl /usr/local/bin/catch-signals.pl
         cmdline = catch-signals.pl

        these lines are equivalent if PATH environment variable includes
        /usr/local/bin and /usr/bin

        Secure way is usage of full path names :-)

        In combination with watch and notify you can add some template
        parameters that will be filled with info at execution time.

         cmdline = send_alert.sh %host% %job% %notify%

        Template name %host% will replaced with hostname where notify
        origins. Template name %job% will replaced with job-name which sends
        the notify. Template name %notify will replaced with notify message
        which can be start-message, success-message, failure-message or
        filename that inotify watch discovered IN_CLOSE_NOWRITE event.

    output
        Default is passthrough and all jobs STDOUT and/or STDERR stream will
        passed through to kubjas STDOUT or log file (if defined with command
        line options).

        Value none disables all output and is "cmdline 2>&1 >/dev/null"
        equivalent.

         output = none

        If param output value is filename then kubjas opens the file with
        append atributes and jobs STDOUT and STDERR will be forwarded to
        this file.

         output = /var/log/job-name.log

    interval
        Specifies time in seconds between job last start. It is the minimum
        delay between the different runs. Actual delay may be longer if
        other conditions prevent running. Null (0) means that job is
        disabled.

        Interval can also be defined as randomized range. Example starts job
        every 20 to 30 seconds.

         interval = 20-30

        There are also four special (non numeric) intervals that activated
        only by outside events: onchange, start-message, success-message,
        failure-message

         interval = onchange
         interval = failure-message

        onchange works with watch parameter. see watch

        start-message, success-message, failure-message will trigger job
        execution then notify message arrives. see notify-start

    period
        Parameter determines if a given time falls within a given period.
        Kubjas executes job only if period is met.

        Period is optional param.

        Theoretically you can emulate crontab with interval and period
        combination. Example job will be run only once a day at 0:00
        midnight

         interval = 60
         period = hr {12am} min {0}

        See also man Time::Period. A sub-period is of the form

         scale {range [range ...]} [scale {range [range ...]}]

        Scale must be one of nine different scales (or their equivalent
        codes):

         Scale  | Scale | Valid Range Values
                | Code  |
         ****************************************************************
         year   |  yr   | n     where n is an integer 0<=n<=99 or n>=1970
         month  |  mo   | 1-12  or  jan, feb, mar, apr, may, jun, jul,
                |       |           aug, sep, oct, nov, dec
         week   |  wk   | 1-6
         yday   |  yd   | 1-365
         mday   |  md   | 1-31
         wday   |  wd   | 1-7   or  su, mo, tu, we, th, fr, sa
         hour   |  hr   | 0-23  or  12am 1am-11am 12noon 12pm 1pm-11pm
         minute |  min  | 0-59
         second |  sec  | 0-59

        crontab comparison [1]

         */5 * * * *  nobody  cmdline

         interval = 300
         user = nobody

        crontab comparison [2]

         0 0 * * * 7  cmdline

         interval = 60
         period = wd {su} hr {12am} min {0}

        or

         interval = 1
         period = wd {7} hr {0} min {0} sec {0}

        crontab comparison [3]

         # run at 2:15pm on the first of every month
         15 14 1 * *  cmdline

         period = md {1} hr {14} min {15} sec {0}

        crontab comparison [4]

         # run at 10 pm on weekdays
         0 22 * * 1-5  cmdline

         period = wd {Mon-Fri} hr {22} min {0} sec {0}

    user
        Run jobs as given user. Kubjas resolves user UID

    group
        Run jobs as given group. Kubjas resolves group GID.

    watch
        Kubjas is monitoring file system events with Linux inotify API if
        you specify list of files and directories to watch.

        One job can have many watch parameters. Kubjas monitors
        IN_CLOSE_NOWRITE events eg. change of file. Example:

         watch = /tmp

        Will trigger job start always the /tmp direcotry changes. Only one
        job at a time.

    notify-start notify-success notify-failure
        Kubjas will notify any other local or remote jobs then current job
        starts and ends. Other job configuration specifies then it runs at
        start-message or success-message. Example you can define two jobs
        that run after each other.

         [job-one]
         notify-success = 127.0.0.1:job-two
         interval = success-message

         [job-two]
         notify-success = 127.0.0.1:job-one
         interval = success-message

        Then job exits with return code other than 0 (with some kind of
        failure) then you can send failure notify to job that fix it or
        notifies administrator.

         [failure-handler]
         cmdline = /usr/local/bin/send_email_to_admin.sh
         interval = failure-message

    conflicts
        This job will only run if no specified jobs are running. Example you
        can have CPU intensive jobs that runs only then other similar jobs
        not running.

         [hard-work]
         conflicts = cpu-work1
         conflicts = hard-work2

        You can have multiple conflicts params.

        conflicts param can be special wildcard value that rule out any jobs
        defined at the same configuration file.

         [spcial-job]
         conflicts = *

    depends
        This job will only run if depends are met. If specified jobs
        allready running. Example you can run periodic jobs only if daemon
        job is running.

         depends = daemon-job
         depends = other-job

        You can have multiple depends params.

        depends param can be special wildcard value that require all other
        jobs to be running that are defined at the same configuration file.

         [ping]
         depends = *

    nice ionice
        Decrease executed job CPU and I/O scheduler priority.

         nice = 1
         ionice = 1

        Will do "renice +10" and "ionice -c 3"

    signal
        Combined with interval special cases you can send UNIX signals to
        running jobs if notify event happen.

         [catch-signals]
         run = daemon
         interval = onchange
         watch = /tmp/date.txt
         signal = USR2

SEE ALSO
    Time::Period(3pm) inotify(7)

FILES
     /etc/kubjas.conf
     /etc/kubjas.d/

AUTHOR
     Kain Kalju <kain@kalju.com>

COPYRIGHT
     Copyright (c) 2014 FlyCom OU.
     This is free software; see the source for copying conditions.  There is
     NO  warranty;  not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.

DATE
    May 8, 2014

