#!/usr/bin/perl -w

# dep: libnet-dns-perl librrds-perl libproc-processtable-perl libappconfig-perl libdatetime-perl

# Puvodne tohle kreslilo i cerveny tecky v miste kde se restartoval racoon, ale to jsem nedoimplentoval na novym ermonu. Byvalo to kvuli tomu ze nektery instituce po restartu racoona dloouho nenajizdely, to se ted uz moc nestava, takze si setrim praci.

use strict;
use Net::DNS;
use RRDs;
use Proc::ProcessTable;
use AppConfig qw(:expand);
use myPerlLDAP::conn;
use myPerlLDAP::entry;
use myPerlLDAP::attribute;
use myPerlLDAP::utils qw(:all);
use Data::Dumper;
use DateTime;
use POSIX qw(strftime);

my $dir = "/home/ipsec_ping/www";
my $pidFile = "/var/run/ipsec_ping/ipsec_ping.pid";
my $racoon = '/home/ipsec_ping/www/radius1edu-racoon/racoon-restarts.rrd';
my @logprefix = ('radius1edu');

my $now    = `date +"%s" -d "now"`;
my $ago2m  = `date +"%s" -d "2 minutes ago"`;
my $ago5m  = `date +"%s" -d "2 minutes ago"`;
my $ago65m = `date +"%s" -d "65 minutes ago"`;
my $ago1d  = `date +"%s" -d "1 days ago"`;
my $ago7d  = `date +"%s" -d "7 days ago"`;
my $fut12h = `date +"%s" -d "+12 hours"`;
my $fut24h = `date +"%s" -d "+24 hours"`-($now-$ago5m);

my %times = (
	     ago8h   => `date +"%s" -d "8 hours ago"`,
	     ago2d   => `date +"%s" -d "2 days ago"`,
	     ago8d   => `date +"%s" -d "8 days ago"`,
	     ago70d  => `date +"%s" -d "70 days ago"`,
	     ago370d => `date +"%s" -d "370 days ago"`,
	    );
my @times = ('ago8h', 'ago2d', 'ago8d', 'ago70d', 'ago370d');
my %times2lang = (
		  ago8h   => "8 hours",
		  ago2d   => "2 days",
		  ago8d   => "8 days",
		  ago70d  => "2 months",
		  ago370d => "one year",
		 );
my @dailyStats = (
		  'uid=semik,ou=People,dc=cesnet,dc=cz',
		 );
my %ip2h;

my $config = AppConfig->new
  ({
    GLOBAL=> { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE => 1
   },
   CFGFilename       => {DEFAULT => '/root/scripts/eduRoam-ping.cfg'},
   LDAPServer        => {DEFAULT => 'localhost'},
   LDAPServerPort    => {DEFAULT => LDAP_PORT},
   UseSSL            => {DEFAULT => undef},
   BindDN            => {DEFAULT => undef},
   BindPassword      => {DEFAULT => ''},
   ServerBase        => {DEFAULT => ''},
   RealmsBase        => {DEFAULT => ''},
   SendMail          => {DEFAULT => undef},
   # Set this to zero and delete all rrd if you wish to rebuild
   # DBs. Default is not to mess with data older that two hours.
   BeginOfOurEpoch   => {DEFAULT => time-2*60*60},
  );

sub max {
  my $a = shift;
  my $b = shift;

  return $a unless defined($b);
  return $b unless defined($a);

  return $a if ($a > $b);
  return $b;
};

sub startRun {
  my $counter = 1;
  while ((-e $pidFile) and ($counter > 0)) {
    warn "File \"$pidFile\" in way, waiting ($counter).";
    sleep 5;
    $counter--;
  };

  if (-e $pidFile) {
    open(PID, "<$pidFile") or die "Can't read file \"$pidFile\"";
    my $pid = <PID>; chomp($pid);
    close(PID);

    my $t = new Proc::ProcessTable;
    my $found = 0;
    foreach my $p ( @{$t->table} ){
      $found = 1 if ($p->pid == $pid);
    };

    if ($found) {
      my $msg = "We are already running as PID=$pid, terminating!";
      die $msg;
    }

    warn "Overwriting orphaned PID file \"$pidFile\"";
  };

  open(RUN, ">$pidFile") or die "Can't create file \"$pidFile\": $!";
  print RUN $$;
  close(RUN);
};

sub stopRun {
  die "Can't remove file \"$pidFile\"! " unless unlink("$pidFile");
};

sub createRRD {
  my $name = shift;
  my $start = shift;

  RRDs::create("$name",
	       "--step=1",
	       "--start=$start", # some time in past
	       "DS:loss:GAUGE:600:0:U",
	       # 1600 values for 800px graph is enought
	       # 12 hours -> 12*60*60/1600 = 27
	       "RRA:MAX:0.5:27:1600",
	       "RRA:MIN:0.5:27:1600",
	       "RRA:AVERAGE:0.5:27:1600",
	       # 2 days -> 2*24*60*60/1600 = 108
	       "RRA:MAX:0.5:108:1600",
	       "RRA:MIN:0.5:108:1600",
	       "RRA:AVERAGE:0.5:108:1600",
	       # 8 dni -> 8*24*60*60/1600 = 432
	       "RRA:MAX:0.5:432:1600",
	       "RRA:MIN:0.5:432:1600",
	       "RRA:AVERAGE:0.5:432:1600",
	       # 70 dni -> 70*24*60*60/1600 = 3780
	       "RRA:MAX:0.5:3780:1600",
	       "RRA:MIN:0.5:3780:1600",
	       "RRA:AVERAGE:0.5:3780:1600",
	       # 370 dni -> 370*24*60*60/1600 = 19980
	       "RRA:MAX:0.5:19980:1600",
	       "RRA:MIN:0.5:19980:1600",
	       "RRA:AVERAGE:0.5:19980:1600",
	      );
};

sub insertLoss {
  my $db = shift;
  my $time = shift;
  my $loss = shift;

  RRDs::update("$db",
	       "$time:$loss");
  my $err = RRDs::error;
  warn "Error while inserting data graph: $err\n" if $err;
};

sub createGraph {
  my $dbname = shift;
  my $graph = shift;
  my $start = shift;
  my $stop = shift;
  my $err;
  my $res = '';
  my @colors = (
		"--color=BACK#ffffff",
		"--color=SHADEA#ffffff",
		"--color=SHADEB#ffffff",
		"--color=CANVAS#ffffff",
		"--color=MGRID#777777",
		"--color=FONT#074a87",
		"--color=FRAME#074a87",
		"--color=ARROW#074a87",
	       );
  my @dimensions = (
		    "--width=700",
		    "--height=60",
		   );
  my $NOW = `date +"%Y.%m.%d %H\\\:%M\\\:%S"`; chomp($NOW);
  my @draw = (
	      "CDEF:y_=100,y,-",
	      "AREA:y_#c1d1e1",
	      "LINE2:y_#074a87",
# ..........................XXXXXXXXX
# .................................YYYYYYYYYYYYYY
# .............................................ZZZZZZZZZZZZ
	      "CDEF:racoon2=racoon,UN,0,racoon,IF,0,UNKN,IF",
	      "LINE3:racoon2#FF0000",
	      "COMMENT:                                                                                       $NOW",
	     );
# X jestlize je promena racoon nedefinovana -> 0, jeli definovana pak 1

# Y pokud je X=1 tak 0 jinak hodnota promene racoon. Tim je zajisteno
# ze cely rozsah na kterem se pracuje ma definovane hodnoty racoon(1)
# pokud doslo k restartu jinak 0

# Z pokud je Y=1 tak se nahradi nulou jinak nedefinovanou
# hodnout. Takze ve vysledku jsou na X ose dubky identifikujici
# okamziky kdy se racoon restartoval.

  my ($averages,$xsize,$ysize) = RRDs::graph(
					     $graph,
#					     "-z",
					     "--start=$start",
					     "--end=$stop",
					     "--upper-limit=100",
					     "--lower-limit=0",
					     @colors,
					     @dimensions,
					     "DEF:y=$dbname:loss:MAX",
					     "DEF:racoon=$racoon:restarts:MAX",
					     @draw,
					    );
  $err = RRDs::error;
  die "Error while creating graph ($dbname): $err\n" if $err;

  return 1;
};

sub dataStart {
  my $rrd = shift;

  return $now unless -f $rrd;

  my ($start,$step,$names,$data) = RRDs::fetch(
					       $rrd,
					       "MAX",
					       "-s ".$times{ago370d},
					       "-e ".$now,
					      );
  return $now unless ($data);
  for (my $i = 0; $i<@{$data}; $i++) {
#    warn "i=$i\n";
#    warn Dumper($data->[$i]->[0]);
    return $start+$i*$step if (defined($data->[$i]->[0]));
  };

  return $now;
};

sub getIP {
  my $hostname = shift;
  my $ip = undef;

  my $res = Net::DNS::Resolver->new;

  my $query = $res->search($hostname);
  return unless $query;

  if ($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "A";
      return $rr->address;
    }
  } else {
    warn "DNS query for $hostname failed: ", $res->errorstring, "\n";
    return undef;
  }

  return undef;
};

sub countReliability {
  sub transfVal {
    my $val = shift;

    return 1 unless (defined($val));
    return 1 if ($val==0);
    return 0;
  };

  my $ip = shift;

  foreach my $prefix (@logprefix) {
    my @res;
    my $db = $ip2h{$ip}->{$prefix}->{ping}->{dbname};
    foreach my $time ($ago65m, $ago1d, $ago7d) {
      my ($start,$step,$names,$data) = RRDs::fetch(
						   $db,
						   "AVERAGE",
						   "-s ".$time,
						   "-e ".$ago5m,
						  );
      my $ok = 0;
      my $err = 0;
      for (my $i = 0; $i<@{$data}-1; $i++) {
	#print "$i: ".transfVal($data->[$i]->[0])."\n";
	if (transfVal($data->[$i]->[0])) {
	  # Pri poslednim zjistovani to fungovalo.
	  $ok++;
	} else {
	  $err++;
	};
      };
      push @res, $ok/($ok+$err);
    };
    $ip2h{$ip}->{$prefix}->{ping}->{reliability} = \@res;
    $ip2h{$ip}->{reliability} = [@res];
  };

  foreach my $prefix (@logprefix) {
    for(my $i=0; $i<3; $i++) {
      $ip2h{$ip}->{reliability}->[$i] = $ip2h{$ip}->{$prefix}->{ping}->{reliability}->[$i]
	if ($ip2h{$ip}->{reliability}->[$i] > $ip2h{$ip}->{$prefix}->{ping}->{reliability}->[$i]);
    };
  };

  return 1;
};

my %host;

startRun;

$config->args(\@ARGV) or
  die "Can't parse cmdline args";
$config->file($config->CFGFilename);# or
#  die "Can't open config file \"".$config->CFGFilename."\": $!";

my $conn = new myPerlLDAP::conn({"host"   => $config->LDAPServer,
				 "port"   => $config->LDAPServerPort,
				 "bind"   => $config->BindDN,
				 "pswd"   => $config->BindPassword,
				 "certdb" => $config->UseSSL}) or
  die "Can't create myPerlLDAP::conn object";

$conn->init or
  die "Can't open LDAP connection to ".$config->LDAPServer.":".$config->LDAPServerPort.": ".$conn->errorMessage;

# Ziskani seznamu hostu ktere bychom meli merit
my $sres = $conn->search($config->ServerBase,
			 LDAP_SCOPE_ONE,
			 '(&(objectClass=eduroamInfRadius)(eduroamInfTransport=IPSEC)(!(radiusDisabled=true)))');
die "Can't search: ".$conn->errorMessage unless $sres;

while (my $entry = $sres->nextEntry) {
  my $cn = $entry->getValues('cn')->[0];

  my $ip = getIP($cn);

  if (defined($ip)) {
    #warn "$cn has $ip\n";

    $ip2h{$ip}->{hostname} = $cn;
    $ip2h{$ip}->{dn} = $entry->dn;
    $ip2h{$ip}->{admins} = $entry->getValues('manager');
    foreach my $realmdn (@{$entry->getValues('eduroamInfRealm')}) {
      my $realm = $conn->read($realmdn);
      foreach my $cn (@{$realm->getValues('cn')}) {
	$ip2h{$ip}->{realms}->{$cn} = 1;
      };
    };
  };
};

# Najit jaky nejstarsi data mame zpracovane pro jednotlive boxy.
foreach my $ip (keys %ip2h) {
  foreach my $prefix (@logprefix) {
    # Pokusime se zjistit jaky nejstarsi zaznam pro ten ktery par boxu
    # mame. Kdyz zadny data mit nebudeme tak dale budeme pracovat s
    # pocatkem epochy. Tj. budem importovat vsechny logy ktere v
    # dalsim kroku najdeme.

    # UPDATE: No nesmi se to prehanet. Protoze kdyz nejaky box umre
    # tak budem potom prohledavat data az do okamziku jeho havarie. A
    # to naprosto zbytecne, takze nasadime urcity omezeni.

    my $dbname = "$dir/$prefix-ping/$ip-ping.rrd";
    $ip2h{$ip}->{$prefix}->{ping}->{dbname} = $dbname;
    $ip2h{$ip}->{$prefix}->{ping}->{lastrecord} = max(RRDs::last("$dbname"), $config->BeginOfOurEpoch);
  };
};

my %log; # logy urcene ke zpracovani
foreach my $prefix (@logprefix) {
  # Najit jake logy mame k dispozici
  my @logfiles = split("\n", `ls -1 /var/log/$prefix-ping*`);

  # Semik 2.8.2018, tohle na novym ermonu asi nebude nastavat, protoze
  # to rovnou rotujeme do lzma, takze musime zvladnout zprocesit vse ten den
  #
  # Zpracovat logy - tedy pokud uz jsme to nedelali nekdy v minulosti.
  foreach my $logfile (@logfiles) {
    if ($logfile =~ /.*(\d{4})\-(\d{2})\-(\d{2})$/) {
      my $logstart = strftime "%s", 0, 0, 0, # h:m:s
	$3, $2-1, $1-1900;
      # Omrknout jestli tenhle logfajl nemuze nekoho zajimat.
      foreach my $ip (keys %ip2h) {
	if ($ip2h{$ip}->{$prefix}->{ping}->{lastrecord} <= $logstart) {
	  $log{$logfile}->{$ip} = $ip2h{$ip}->{$prefix}->{ping}->{dbname};
	};
      };
    };
  };

  # Pridat aktualne prijimane logy
  my $dt = DateTime->now;
  my $today = $dt->ymd;
  foreach my $ip (keys %ip2h) {
    $log{"/var/log/$prefix-ping-$today"}->{$ip} = $ip2h{$ip}->{$prefix}->{ping}->{dbname};
  };
};

my %knownDBs;

# Tak a pomalu zacneme ty data opravdu zpracovavat
foreach my $logfile (sort keys %log) {
  warn "Processing: $logfile\n";

  my $h = $log{$logfile}; # masiny co maji o tenhle log zajem

  my $cat = "cat"; $cat = "bzcat" if ($logfile =~ /.bz2$/);
  my $cmd = "$cat $logfile | sed 's/.*]: //;' | sort -n |";
  open(LOG, $cmd) or die "Can't exec \"$cmd\": $?";
  while (my $line=<LOG>) {
    chomp($line);

#    if (($line =~ /^(\d+): (\d+\.\d+\.\d+\.\d+): \d+ packets transmitted, \d+ .*received, (\d+)% packet loss/) or
#        ($line =~ /^(\d+): (\d+\.\d+\.\d+\.\d+): *$/)) {
    if ($line =~ /^(\d+): (\d+\.\d+\.\d+\.\d+): \d+ packets transmitted, \d+ .*received, (\d+)% packet loss/) {
      my $time = $1;
      my $ip = $2;
      my $loss = $3; $loss = 100 unless (defined($loss));

      if (($time < $ago2m) and (exists($h->{$ip}))) {
	# Cas neni prilis blizko a soucasne tenhle box nema jeste
	# tyhle data zpracovany.
	unless ($knownDBs{$h->{$ip}}) {
	  # Nevime jestli tahle databaze existuje, takze to
	  # prozkoumame a pripadne ji vytvorime.
	  unless (-f $h->{$ip}) {
	    # Databaze neexistuje. Takze log fajl co ted budeme
	    # zpracovavat je to nejstarsi co mame k dispozici. Proto
	    # ho pouzimeme jako pocatek. Pokud nedokazem naparsovat
	    # datum z jmena logfailu zacnem dva dny v minulosti.
	    my $start = $times{ago2d};
	    if ($logfile =~ /.*(\d{4})_(\d{2})_(\d{2})/) {
	      $start = strftime "%s", 0, 0, 0, # h:m:s
		$3, $2-1, $1-1900;
	    };
	    warn "Creating DB \"".$h->{$ip}."\" starting from $start\n";
	    createRRD($h->{$ip}, $start);
	  };
	  $knownDBs{$h->{$ip}} = RRDs::last($h->{$ip}) || 1;
	};
	
	if ($time > $knownDBs{$h->{$ip}}) {
	  insertLoss($h->{$ip}, $time, $loss);
	  $knownDBs{$h->{$ip}} = $time;
	};
      };
    };
  };
  close (LOG);
};

foreach my $ip (keys %ip2h) {
  foreach my $prefix (@logprefix) {
    foreach my $service ('ping') {
      my $db = $ip2h{$ip}->{$prefix}->{$service}->{dbname};
      unless ( -f $db ) {
	# Databaze pro tohle IPcko neexistuje a soucasne o tomhle
	# IPcku neni zadny zazam v logach. Takze vytvorime prazdnou,
	# protoze jinak se ty logy budou projizdet pri kazdym dalsi
	# spuseteni tohle skriptu.
	my $start = $now;
	warn "Creating empty DB \"$db\" starting from $start\n";
	createRRD($db, $start);
      };
    };
  };
};

foreach my $ip (keys %ip2h) {
  foreach my $prefix (@logprefix) {
    foreach my $time (keys %times) {
      my $graphName = "$dir/$prefix-ping/$ip-ping-$time.png";

      my $start = dataStart($ip2h{$ip}->{$prefix}->{ping}->{dbname});

      if (($start <= ($now-($now-$times{$time})/4)) or
          ($time eq 'ago2d') or ($time eq 'ago8h')) {
	createGraph($ip2h{$ip}->{$prefix}->{ping}->{dbname},
		    $graphName,
		    $times{$time}, $now);
	$ip2h{$ip}->{$prefix}->{ping}->{$time."Graph"} = $graphName;
      } else {
	unlink($graphName);
      };

    };
  };
};

# Vygenerovani indexu
my $index = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"\">
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head>
  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-2\"/>
  <title>eduroam.cz: IPsec conections reliability stats (".`date +'%c'`.")</title>
</head>
<body bgcolor=\"white\">
<h1>IPsec connection reliabity stats for <i>eduroam.cz</i></h1>
<table>\n";

#$sres = $conn->search($config->RealmsBase,
#		      LDAP_SCOPE_SUBTREE,
#		      '(objectClass=eduRoamRealm)');
#while (my $entry = $sres->nextEntry) {
#  my $cn = $entry->getValues('cn')->[0];

#  foreach my $hostDN (@{$entry->getValues('eduRoamRadiusHostname')}) {
#    my $hostEntry = $conn->read($hostDN);
#    my $host = $hostEntry->getValues('cn')->[0];
#    my $ip = getIP($host);
#    $ip2h{$ip}->{realms}->{$cn} = 1 if ($ip);
#  };
#};

my %realms;
foreach my $ip (sort keys %ip2h) {
  push @{$realms{join(', ', keys %{$ip2h{$ip}->{realms}})}}, $ip2h{$ip};
};

foreach my $realm (sort keys %realms) {
  $index .= "<tr><th bgcolor=\"#074a87\" align=\"left\" colspan=\"3\"><font size=\"+2\" color=\"white\">Realm: $realm</font></th></tr>\n";
  foreach my $host (@{$realms{$realm}}) {
    foreach my $prefix (@logprefix) {
      my $img = $host->{$prefix}->{ping}->{ago2dGraph};
      $img =~ s/^$dir\/*//;
      $index .= "<tr><td bgcolor=\"#c1d1e1\">&nbsp;&nbsp;</th><td align=\"left\" colspan=\"2\">IPsec connection stats (in last two days): <b><a href=\"".getIP($host->{hostname}).".html\">".$host->{hostname}."</a> &lt;-&gt; ".$prefix."</b></td></tr>\n";
      $index .= "<tr><td bgcolor=\"#c1d1e1\"/><td/><td><img src=\"$img\" width=\"781\" height=\"128\"/></td></tr>";
    };
  };
  $index .= "<tr><td>&nbsp;</td></td>";
};

$index .= "</table>
</body>
</html>\n";

open (HTML, ">$dir/index.html");
print HTML $index;
close (HTML);

foreach my $ip (keys %ip2h) {
  my $html = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"\">
<html xmlns=\"http://www.w3.org/1999/xhtml\">
<head>
  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-2\"/>
  <title>eduroam.cz: IPsec conections reliability stats for $ip (".`date +'%c'`.")</title>
</head>
<body bgcolor=\"white\">\n";
  $html .= "<h1>Stats for ".$ip2h{$ip}->{hostname}." &lt;-&gt; radius1/2.eduroam.cz</h1><br/>";
  $html .= "<table>\n";
  $html .= "<!--tr><th>Time period</th><th>Graph for radius1.eduroam.cz resp radius2.eduroam.cz</th></tr-->\n";
  foreach my $time (@times) {
    my @fnames;
    foreach my $prefix (@logprefix) {
      my $f = $ip2h{$ip}->{$prefix}->{ping}->{$time.'Graph'};
      if (defined($f)) {
	$f =~ s/$dir\/*//;
	push @fnames, $f;
      };	
    };
    if (@fnames) {
      $html .= "<tr bgcolor=\"#c1d1e1\"><td bgcolor=\"white\" nowrap=\"nowrap\" valign=\"top\">&nbsp;$times2lang{$time}&nbsp;</td><td>";
      $html .= join("<br/>\n", map {"<img src=\"$_\" width=\"781\" height=\"128\"/>"}  @fnames);
      $html .= "</td></tr>\n";
    };
  };
  $html .= "</table>
</body>
</html>\n";

  open (HTML, ">$dir/$ip.html");
  print HTML $html;
  close (HTML);
};

# Tak a jeste mailovani
foreach my $ip (keys %ip2h) {
  countReliability($ip);
};

my %mailto;
my $counter = 1;
my $mail = "Prehled dostupnosti vsech pripojenych serveru:\n\n"; 
   $mail.= " #. |        7dni |    24 hodin |      60 min | Jmeno\n";
   $mail.= "----+-------------+-------------+-------------+-------------------------------\n";
foreach my $ip (reverse
		sort {$ip2h{$a}->{reliability}->[2] <=> $ip2h{$b}->{reliability}->[2]} keys %ip2h) {
  $mail .= sprintf("%.2d. | ", $counter++);
  for (my $i=2; $i>=0; $i--) {
    my @rel;
    foreach my $prefix (@logprefix) {
      push @rel, sprintf "% 5s",
	sprintf "%3.1f", $ip2h{$ip}->{$prefix}->{ping}->{reliability}->[$i]*100;
    };
    $mail .= join('/', @rel).' | ';
  };
  $mail .= $ip2h{$ip}->{hostname}."\n";

  my $notif = "$dir/$ip\.notification";
  if ($ip2h{$ip}->{reliability}->[0] < 0.8) {
    my $send = 1;

    if (-f $notif) {
      open(NOT, "<$notif");
      my $last = <NOT>; chomp($last);
      close(NOT);
      if ($last < $now) {
	open(NOT, ">$notif");
	print NOT $fut12h;
	close(NOT);
      } else {
	$send = 0;
      };
    } else {
      open(NOT, ">$notif");
      print NOT $fut12h;
      close(NOT);
    };

    if ($send) {
      foreach my $admin (@{$ip2h{$ip}->{admins}}) {
	#$mailto{'uid=semik,ou=People,dc=cesnet,dc=cz'}->{$ip} = 1;
	$mailto{$admin}->{$ip} = 1;
      };
    };
  } else {
    unlink($notif);
  };
};

$mail .= "\nNa adrese https://ermon.cesnet.cz/eps2 naleznete grafy dostupnosti
jednotlivych serveru.

S pozdravem
  $0 bezici na ".`hostname`;

if (%mailto) {
  foreach my $dn (keys %mailto) {
    my $admin = $conn->read($dn);
    my @servery = map {$ip2h{$_}->{hostname}} keys %{$mailto{$dn}};
    my $m = "From: Jan.Tomasek\@cesnet.cz
To: ".$admin->getValues('mail')->[0]."
Subject: Vypadek IPsec spojeni serveru ".join(', ', @servery)."

Behem posledni hodiny byla spolehlivost IPsec spojeni serveru:

  ".join("\n  ", @servery)."

nizsi nez 80%.\n\n$mail";

#    warn "Sending:\n$m-----------------------------------------------------------\n";

#    open(SENDMAIL, "| /usr/sbin/sendmail -t");
#    print SENDMAIL $m;
#    close(SENDMAIL);
  };
};

# Poslani denni statistiky
my $daily = "$dir/daily-report";
unless (-f $daily) {
  # Fail v kterym je cas posledni denni notifikace chybi tak ho
  # udelame s casem v minulosti

  open(NOT, ">$daily");
  print NOT $ago7d;
  close(NOT);
};

open(NOT, "<$daily");
my $daily_sent = <NOT>; chomp($daily_sent);
close(NOT);

if ($daily_sent <= $ago1d) {
#  my @to;
#  foreach my $dn (@dailyStats) {
#    my $entry = $conn->read($dn);
#    push @to, $entry->getValues('mail')->[0];
#  };
#  my $m = "From: Jan.Tomasek\@cesnet.cz
#To: ".join(', ', @to)."
#Subject: Daily IPsec stats
#
#$mail";
#
#  open(SENDMAIL, "| /usr/sbin/sendmail -t");
#  print SENDMAIL $m;
#  close(SENDMAIL);

  open(NOT, ">$daily");
  print NOT $ago2m;
  close(NOT);
};

$conn->close;
stopRun;
