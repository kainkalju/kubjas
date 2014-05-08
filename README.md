<html>
<head>
<title>kubjas - daemon to execute scheduled commands</title>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<link rev="made" href="mailto:root@localhost" />
</head>

<body style="background-color: white">


<!-- INDEX BEGIN -->
<div name="index">
<p><a name="__index__"></a></p>

<ul>

	<li><a href="#name">NAME</a></li>
	<li><a href="#synopsis">SYNOPSIS</a></li>
	<li><a href="#description">DESCRIPTION</a></li>
	<li><a href="#configuration">CONFIGURATION</a></li>
	<li><a href="#see_also">SEE ALSO</a></li>
	<li><a href="#files">FILES</a></li>
	<li><a href="#author">AUTHOR</a></li>
	<li><a href="#copyright">COPYRIGHT</a></li>
	<li><a href="#date">DATE</a></li>
</ul>

<hr name="index" />
</div>
<!-- INDEX END -->

<p>
</p>
<hr />
<h1><a name="name">NAME</a></h1>
<p>kubjas - (cron like) daemon to execute scheduled commands</p>
<p>
</p>
<hr />
<h1><a name="synopsis">SYNOPSIS</a></h1>
<p>kubjas.pl [--background] [--conf_file /etc/kubjas.conf] [--log_file /path/kubjas.log] [--pid_file /path/kubjas.pid]</p>
<p>
</p>
<hr />
<h1><a name="description">DESCRIPTION</a></h1>
<p>Kubjas is periodic job scheduler that operates with minimum 1 second intervals.</p>
<p>Kubjas is not another cron daemon. Kubjas does not start programs at certain
time but at specified intervals. Kubjas also includes <strong>Time::Period</strong> filter.
You can configure <strong>interval</strong> and <strong>period</strong> combinations that act like crontab.</p>
<p>Kubjas measures executed job running times and log it when job exits.
Measurements are in milliseconds resolution.</p>
<p>Kubjas configuration is standard INI file format. You can have multiple
configuration files at same time. Main configuration is <strong>/etc/kubjas.conf</strong>
and <strong>/etc/kubjas.d/</strong> directory is for additional configurations. Each job can have
her own config file. You can force configuration reload with <strong>HUP</strong> signal.</p>
<p>
</p>
<hr />
<h1><a name="configuration">CONFIGURATION</a></h1>
<dl>
<dt><strong><a name="example_conf" class="item">example.conf</a></strong></dt>

<dd>
<pre>
 [*]
 notify-failure = 192.168.1.27:catch-signals</pre>
<pre>
 [date-job]
 cmdline = date +&quot;%H:%M&quot; &gt; /var/tmp/date.txt
 interval = 60
 user = nobody
 group = nogroup
 notify-success = 192.168.1.27:catch-signals</pre>
<pre>
 [catch-signals]
 cmdline = /usr/local/bin/catch-signals.pl
 output = none
 interval = failure-message
 signal = USR2</pre>
<pre>
 [readfile]
 cmdline = /usr/local/bin/readfile.sh
 interval = onchange
 watch = /var/tmp/date.txt
 output = /tmp/date.log
 user = nobody
 group = nogroup</pre>
<pre>
 [very-shy-job]
 cmdline = /usr/local/bin/shy.sh
 interval = 10-20
 period = wd {1 3 5 7} min {0-29}, wd {2 4 6} min {30-59}
 depends = catch-signals
 conflicts = date-job
 nice = 1
 ionice = 1</pre>
</dd>
<dt><strong><a name="job_name" class="item">job-name</a></strong></dt>

<dd>
<p>[job-name] is the INI file section. Job names must be unique.</p>
<p>Special section name [*] sets default params that will be used
with all jobs defined at the same configuration file. Named job
sections overwrite default params.</p>
</dd>
<dt><strong><a name="cmdline" class="item">cmdline</a></strong></dt>

<dd>
<p>Parameter <strong>cmdline</strong> define executable program with parameters</p>
<pre>
 cmdline = perl /usr/local/bin/catch-signals.pl
 cmdline = catch-signals.pl</pre>
<p>these lines are equivalent if <strong>PATH</strong> environment variable 
includes /usr/local/bin and /usr/bin</p>
<p>Secure way is usage of full path names :-)</p>
<p>In combination with <strong>watch</strong> and <strong>notify</strong> you can add some template
parameters that will be filled with info at execution time.</p>
<pre>
 cmdline = send_alert.sh %host% %job% %notify%</pre>
<p>Template name <strong>%host%</strong> will replaced with hostname where notify origins.
Template name <strong>%job%</strong> will replaced with job-name which sends the notify.
Template name <strong>%notify%</strong> will replaced with notify message which can be
<strong>start-message</strong>, <strong>success-message</strong>, <strong>failure-message</strong> or <strong>filename</strong>
that inotify <strong>watch</strong> discovered <strong>IN_CLOSE_WRITE</strong> event.</p>
</dd>
<dt><strong><a name="output" class="item">output</a></strong></dt>

<dd>
<p>Default is <strong>passthrough</strong> and all jobs STDOUT and/or STDERR stream will
passed through to kubjas STDOUT or log file (if defined with command line
options).</p>
<p>Value <strong>none</strong> disables all output and is &quot;cmdline 2&gt;&amp;1 &gt;/dev/null&quot; equivalent.</p>
<pre>
 output = none</pre>
<p>If param output value is filename then kubjas opens the file with append
atributes and jobs STDOUT and STDERR will be forwarded to this file.</p>
<pre>
 output = /var/log/job-name.log</pre>
</dd>
<dt><strong><a name="interval" class="item">interval</a></strong></dt>

<dd>
<p>Specifies time in seconds between job last start. It is the minimum
delay between the different runs. Actual delay may be longer if other
conditions prevent running. Null (0) means that job is disabled.</p>
<p>Interval can also be defined as randomized range. Example starts job every
20 to 30 seconds.</p>
<pre>
 interval = 20-30</pre>
<p>There are also four special (non numeric) intervals that activated 
only by outside events: <strong>onchange</strong>, <strong>start-message</strong>, <strong>success-message</strong>,
<strong>failure-message</strong></p>
<pre>
 interval = onchange
 interval = failure-message</pre>
<p><strong>onchange</strong> works with <strong>watch</strong> parameter. see <strong>watch</strong></p>
<p>start-message, success-message, failure-message will trigger job
execution then notify message arrives. see <strong>notify-start</strong></p>
</dd>
<dt><strong><a name="period" class="item">period</a></strong></dt>

<dd>
<p>Parameter determines if a given time falls within a given period.
Kubjas executes job only if period is met.</p>
<p>Period is optional param.</p>
<p>Theoretically you can emulate <strong>crontab</strong> with <strong>interval</strong> and <strong>period</strong>
combination. Example job will be run only once a day at 0:00 midnight</p>
<pre>
 interval = 60
 period = hr {12am} min {0}</pre>
<p>See also man <strong>Time::Period</strong>. A sub-period is of the form</p>
<pre>
 scale {range [range ...]} [scale {range [range ...]}]</pre>
<p>Scale must be one of nine different scales (or their equivalent codes):</p>
<pre>
 Scale  | Scale | Valid Range Values
        | Code  |
 ****************************************************************
 year   |  yr   | n     where n is an integer 0&lt;=n&lt;=99 or n&gt;=1970
 month  |  mo   | 1-12  or  jan, feb, mar, apr, may, jun, jul,
        |       |           aug, sep, oct, nov, dec
 week   |  wk   | 1-6
 yday   |  yd   | 1-365
 mday   |  md   | 1-31
 wday   |  wd   | 1-7   or  su, mo, tu, we, th, fr, sa
 hour   |  hr   | 0-23  or  12am 1am-11am 12noon 12pm 1pm-11pm
 minute |  min  | 0-59
 second |  sec  | 0-59</pre>
<p>crontab comparison [1]</p>
<pre>
 */5 * * * *  nobody  cmdline</pre>
<pre>
 interval = 300
 user = nobody</pre>
<p>crontab comparison [2]</p>
<pre>
 0 0 * * * 7  cmdline</pre>
<pre>
 interval = 60
 period = wd {su} hr {12am} min {0}</pre>
<p>or</p>
<pre>
 interval = 1
 period = wd {7} hr {0} min {0} sec {0}</pre>
<p>crontab comparison [3]</p>
<pre>
 # run at 2:15pm on the first of every month
 15 14 1 * *  cmdline</pre>
<pre>
 period = md {1} hr {14} min {15} sec {0}</pre>
<p>crontab comparison [4]</p>
<pre>
 # run at 10 pm on weekdays
 0 22 * * 1-5  cmdline</pre>
<pre>
 period = wd {Mon-Fri} hr {22} min {0} sec {0}</pre>
</dd>
<dt><strong><a name="user" class="item">user</a></strong></dt>

<dd>
<p>Run jobs as given user. Kubjas resolves user UID</p>
</dd>
<dt><strong><a name="group" class="item">group</a></strong></dt>

<dd>
<p>Run jobs as given group. Kubjas resolves group GID.</p>
</dd>
<dt><strong><a name="watch" class="item">watch</a></strong></dt>

<dd>
<p>Kubjas is monitoring file system events with Linux inotify API if
you specify list of files and directories to <strong>watch</strong>.</p>
<p>One job can have many watch parameters. Kubjas monitors <strong>IN_CLOSE_WRITE</strong>
events eg. change of file. Example:</p>
<pre>
 watch = /tmp</pre>
<p>Will trigger job start always the /tmp directory changes. Only one
job at a time.</p>
</dd>
<dt><strong><a name="notify_start_notify_success_notify_failure" class="item">notify-start notify-success notify-failure</a></strong></dt>

<dd>
<p>Kubjas will notify any other local or remote jobs then current job starts and
ends. Other job configuration specifies then it runs at <strong>start-message</strong> or
<strong>success-message</strong>. Example you can define two jobs that run after each other.</p>
<pre>
 [job-one]
 notify-success = 127.0.0.1:job-two
 interval = success-message</pre>
<pre>
 [job-two]
 notify-success = 127.0.0.1:job-one
 interval = success-message</pre>
<p>Then job exits with return code other than 0 (with some kind of failure) then
you can send failure notify to job that fix it or notifies administrator.</p>
<pre>
 [failure-handler]
 cmdline = /usr/local/bin/send_email_to_admin.sh
 interval = failure-message</pre>
</dd>
<dt><strong><a name="conflicts" class="item">conflicts</a></strong></dt>

<dd>
<p>This job will only run if no specified jobs are running. Example you can
have CPU intensive jobs that runs only then other similar jobs not running.</p>
<pre>
 [hard-work]
 conflicts = cpu-work1
 conflicts = hard-work2</pre>
<p>You can have multiple <strong>conflicts</strong> params.</p>
<p>conflicts param can be special wildcard value that rule out any jobs
defined at the same configuration file.</p>
<pre>
 [spcial-job]
 conflicts = *</pre>
</dd>
<dt><strong><a name="depends" class="item">depends</a></strong></dt>

<dd>
<p>This job will only run if depends are met. If specified jobs allready running.
Example you can run periodic jobs only if other job is running.</p>
<pre>
 depends = other-job</pre>
<p>You can have multiple <strong>depends</strong> params.</p>
<p>depends param can be special wildcard value that require all other jobs to
be running that are defined at the same configuration file.</p>
<pre>
 [ping]
 depends = *</pre>
</dd>
<dt><strong><a name="nice_ionice" class="item">nice ionice</a></strong></dt>

<dd>
<p>Decrease executed job CPU and I/O scheduler priority.</p>
<pre>
 nice = 1
 ionice = 1</pre>
<p>Will do &quot;renice +10&quot; and &quot;ionice -c 3&quot;</p>
</dd>
<dt><strong><a name="signal" class="item">signal</a></strong></dt>

<dd>
<p>Combined with <strong>interval</strong> special cases you can send UNIX signals to running
jobs if notify event happen.</p>
<pre>
 [catch-signals]
 interval = onchange
 watch = /tmp/date.txt
 signal = USR2</pre>
</dd>
</dl>
<p>
</p>
<hr />
<h1><a name="see_also">SEE ALSO</a></h1>
<p>Time::Period(3pm)
<code>inotify(7)</code></p>
<p>
</p>
<hr />
<h1><a name="files">FILES</a></h1>
<pre>
 /etc/kubjas.conf
 /etc/kubjas.d/</pre>
<p>
</p>
<hr />
<h1><a name="author">AUTHOR</a></h1>
<pre>
 Kain Kalju &lt;kain@kalju.com&gt;</pre>
<p>
</p>
<hr />
<h1><a name="copyright">COPYRIGHT</a></h1>
<pre>
 Copyright (c) 2014 FlyCom OU.
 This is free software; see the source for copying conditions.  There is
 NO  warranty;  not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.</pre>
<p>
</p>
<hr />
<h1><a name="date">DATE</a></h1>
<p>May 8, 2014</p>

</body>

</html>
