#!/usr/bin/perl -w

use strict;
#use perlOpenLDAP::API qw(LDAP_PORT LDAPS_PORT LDAP_SCOPE_SUBTREE LDAP_SCOPE_ONELEVEL);
use myPerlLDAP::utils qw(:all);
use myPerlLDAP::conn;
use DBI;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Date::Manip;
use AppConfig qw(:expand);
use RRDs;
use Net::DNS;
use POSIX qw(strftime);

# 24. 4. 2007 - pridana rada radku k ignorovani coz je nutne po
#               zvyseni trace urovne radiusu.
#             - upravena tabulka proxyrealm aby pojmula delsi
#               string... tohle udela zase v budoucnu problem.

my %days = (
	    31    => 'month',
	    3*31  => '3 months',
	    370   => 'year',
	    5*365 => '5 years'
	   );

sub getIP {
  my $hostname = shift;

  my $res   = Net::DNS::Resolver->new;
  my $query = $res->search($hostname);

  if ($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "A";
      return $rr->address;
    }
  } else {
    #die "DNS query failed: ", $res->errorstring, "\n";
    return undef;
  }

  # This should not happen
  die "Neco strasnyho co se stat nemelo se stalo";
}

sub cmpDomainNames {
  my $a = shift;
  my $b = shift;
  my @a = reverse split('\.', $a);
  my @b = reverse split('\.', $b);

  for (my $i=0; ($i < @a) and ($i < @b); $i++) {
    my $cmp = $a[$i] cmp $b[$i];
    return $cmp unless ($cmp == 0);
  };

  return  1 if (scalar(@a) > scalar(@b));
  return -1 if (scalar(@a) < scalar(@b));
  return 0;
};

sub getIP2ServerName {
  my $conn = shift;
  my $base = shift;

  # Read ALL defined eduroam RADIUS servers, except of those disabled
  my $sres = $conn->search($base,
			   LDAP_SCOPE_ONE,
			   '(&(objectClass=eduroamRadius)(!(radiusDisabled=*)))')
    or die "Can't search: ".$conn->errorMessage;

  my %servers;
  while (my $server = $sres->nextEntry) {
    my $cn = $server->getValues('cn')->[0];

    # We are only interested in servers in DNS. Belive or not, admins
    # are sometimes by misstake deleting entries from their domains.
    next unless (my $IP = getIP($cn));

    $servers{$IP}->{name} = $cn;
    $servers{$IP}->{IP}   = $IP;
    $servers{$IP}->{DN}   = $server->dn;

    my @realms;
    foreach my $realmdn (@{$server->getValues('eduroamInfRealm')}) {
      my $realm = $conn->read($realmdn);
      if ($realm) {
	push @realms, @{$realm->getValues('cn')};
      };
    };
    $servers{$IP}->{realms} = join(', ', sort {cmpDomainNames($a, $b)} @realms);
  };

  return \%servers;
};

my @testRealms = ('radius1.cesnet.cz', 'radius2.cesnet.cz', 'cesnet.cz',
		  'etest.eduroam.cz', 'test.eduroam.cz',	
		  'radius1.eduroam.cz', 'radius2.eduroam.cz');

sub getTestingAccounts {
  my $conn = shift;
  my $otherBase = shift; # testing realms of other institutions
  my $ourBase = shift; # testing ID with our realms

  my %accounts;

  my $sres = $conn->search($ourBase,
			   LDAP_SCOPE_ONE,
			   '(objectClass=eduroamTestAccount)')
    or die "Can't search: ".$conn->errorMessage;
  while (my $testID = $sres->nextEntry) {
    my $uid = $testID->getValues('uid')->[0];
    # Jsem pomerne dost kreativni co se tyce pouzitelnych realmu,
    # takze...
    foreach my $realm (@testRealms) {
      $accounts{"$uid\@$realm"}->{id} = "$uid\@$realm";
    };
  };

  foreach my $realm (@testRealms) {
    $accounts{"nagios\@$realm"}->{id} = "nagios\@$realm";
  };


  $sres = $conn->search($otherBase,
			LDAP_SCOPE_ONE,
			'(objectClass=eduroamRealm)')
    or die "Can't search: ".$conn->errorMessage;
  while (my $testID = $sres->nextEntry) {
    my $testingID = $testID->getValues('eduroamTestingID')->[0] || undef;
    $accounts{$testingID}->{id} = $testingID if defined($testingID);
  };

  return \%accounts;
};

sub getID {
  my $dbh = shift;
  my $table = shift;
  my $object = shift;
  my $objectCache = shift;
  my $autoAdd = shift || 0;

  return $objectCache->{$object} if defined($objectCache->{$object});

  my $sql = "SELECT * FROM $table WHERE  $table=".$dbh->quote($object);
  my $sth = $dbh->prepare($sql);
  if ($sth->execute) {
    my $row = $sth->fetchrow_hashref;
    if ($row) {
      $objectCache->{$object} = $row->{id};
      return $row->{id};
    } else {
      # V databazi neni tenhle object.
      return unless ($autoAdd);

      my $sql2 = "INSERT INTO $table SET $table=".$dbh->quote($object);
      if ($dbh->do($sql2)) {
	if ($sth->execute) {
	  my $row = $sth->fetchrow_hashref;
	  if ($row) {
	    $objectCache->{$object} = $row->{id};
	    return $row->{id};
	  };
	};
      }
    };
  } else {
    warn "FailedSQL: $sql\n";
  };

  return undef;
};

sub getAnonymousID {
  my $dbh = shift;
  my $username = shift;
  my $anonymCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'user', $username, $anonymCache, $autoAdd);
};

sub getProxyRealmsID {
  my $dbh = shift;
  my $realms = shift;
  my $realmsCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'proxyrealms', $realms, $realmsCache, $autoAdd);
};

sub getProxyID {
  my $dbh = shift;
  my $proxy = shift;
  my $proxyCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'proxy', $proxy, $proxyCache, $autoAdd);
};

sub getCSIDID {
  my $dbh = shift;
  my $csid = shift;
  my $csidCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'csid', $csid, $csidCache, $autoAdd);
};

sub getNASID {
  my $dbh = shift;
  my $nasid = shift;
  my $nasidCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'nasid', $nasid, $nasidCache, $autoAdd);
};

sub getNASIPID {
  my $dbh = shift;
  my $nasip = shift;
  my $nasipCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'nasip', $nasip, $nasipCache, $autoAdd);
};

sub getRealmID {
  my $dbh = shift;
  my $realm = shift;
  my $realmCache = shift;
  my $autoAdd = shift || 0;

  return getID($dbh, 'realm', $realm, $realmCache, $autoAdd);
};

# Funkce sesype vezme z tabulky romaing prvni uspesny login uzivatele
# a soupne ho do tabulky sucrom. Je to takhle slozity jelikoz pri
# experimentech s group by user se mi nepodarilo dosahnout toho aby na
# vystupu byl prvni cas prihlaseni.
sub aggregateDate {
  my $dbh = shift;
  my $date = shift;

  # ziskat seznam uzivatelu co se ten den logli
  my $sql = "SELECT user FROM roaming WHERE date='$date' AND result='access-accept' GROUP BY user";
  my $sth = $dbh->prepare($sql);
  if ($sth->execute) {
    while (my $row = $sth->fetchrow_hashref) {
#      warn $sql;
#      warn Dumper($row);
#      warn "$date: ".$row->{user}."\n";
      my $sql2 = "REPLACE INTO sucrom SELECT id,date,time,user,realm,monitoring,proxy,proxyrealms,eap FROM roaming WHERE DATE='$date' AND user=".$row->{user}." AND result='access-accept' ORDER BY date,time LIMIT 1";
      unless ($dbh->do($sql2)) {
	return undef;
      };
    };
    return 1;
  } else {
    return undef;
  };
};

# Funkce znovu zagrehuje tabulku roaming do sucrom. NEMAZE tabulku
# sucrom ale pouziva REPLACE INTO, v pripade potreby je treba tabulku
# sucrom smazat rucne.
sub reagregateAll {
  my $dbh = shift;

  my $sql = "SELECT date FROM roaming WHERE date >= '2014-06-01' GROUP BY date ORDER BY date";
  my $sth = $dbh->prepare($sql);
  if ($sth->execute) {
    while (my $row = $sth->fetchrow_hashref) {
      warn "Working on: ".$row->{date}."\n";
      aggregateDate($dbh, $row->{date});
    };
  };
};

# Funkce vytvori rrd databazi - pokud neexistuje
sub createRRDDB {
  my $db = shift;
  my $start = shift;

  return 1 if (-f "$db");

#  RRDs::create("$db",
#	       "--step=1",
#	       "--start=$start",
#	       # 2 days = 7*24*60*60 = 172800
#	       "DS:value:GAUGE:604800:0:U",
#	       # 1600 values for 800px graph is enought
#	       # 3 months -> 3*31*24*60*60/1600 = 5022
#	       "RRA:MAX:0.5:5022:1600",
#	       "RRA:MIN:0.5:5022:1600",
#	       "RRA:AVERAGE:0.5:5022:1600",
#	       # 1 year = 365 days -> 365*24*60*60/1600 = 19710
#	       "RRA:MAX:0.5:19710:1600",
#	       "RRA:MIN:0.5:19710:1600",
#	       "RRA:AVERAGE:0.5:19710:1600",
#	       # 5 years = 5*365*24*60*60/1600 = 98550
#	       "RRA:MAX:0.5:98550:1600",
#	       "RRA:MIN:0.5:98550:1600",
#	       "RRA:AVERAGE:0.5:98550:1600",
#	      );

#  RRDs::create("$db",
#	       "--step=86400", # 1day = 86400
#	       "--start=$start",
#	       "DS:value:GAUGE:172800:0:U",
#	       # 1600 values for 800px graph is enought - HAHAHA. Kde bych je nabral.
#	       # 3 months = 3 * 31 = 93
##	       "RRA:MAX:0.5:1:93",
##	       "RRA:MIN:0.5:1:93",
##	       "RRA:AVERAGE:0.5:1:93",
#	       # 1 year = 365
##	       "RRA:MAX:0.5:1:365",
##	       "RRA:MIN:0.5:1:365",
##	       "RRA:AVERAGE:0.5:1:365",
#	       # 5 years = 5*365 = 1825
#	       "RRA:MAX:0.5:1:1825",
#	       "RRA:MIN:0.5:1:1825",
#	       "RRA:AVERAGE:0.5:1:1825",
#	      );

  RRDs::create("$db",
	       "--step=3600", # 1hour = 3600
	       "--start=$start",
	       "DS:value:GAUGE:86400:0:U", # day = 24*3600 = 86400
	       # 5 years in hours = 5*365*24 = 43800
	       # 5*365*24/6 = 7300
	       "RRA:MAX:0:6:7300",
	       "RRA:MIN:0:6:7300",
	       "RRA:AVERAGE:0:6:7300",
	      );


  my $err = RRDs::error;
  die "Error while creating graph: $err\n" if $err;

  return 1;
};

sub buildGraph {
  my $dbh = shift;
  my $config = shift;
  my $realms = shift;

  my $filter = 'monitoring=0';
  $filter = "proxyrealms=$realms AND $filter" unless ($realms eq 'all');

  my $fb = $config->RRDDir."/".$realms; # filename base
  my $db = $fb.".rrd";
  my $start;
  my $stop;

  # Mrknout jestli mame RRD databazi
  unless (-f $db) {
    # Zjisit odkdy mame data
    my $sql = "SELECT UNIX_TIMESTAMP(CONCAT(date,' ',time)) AS timestamp FROM sucrom WHERE $filter ORDER BY timestamp ASC LIMIT 1";
    my $sth = $dbh->prepare($sql);
    if ($sth->execute > 0) {
      my $row = $sth->fetchrow_hashref;
#      warn Dumper($row);
      $start = $row->{timestamp};
      createRRDDB($db, $start-1);
    };
  } else {
    # Zjisit DO kdy je rrd naplneno
    $start = RRDs::last($db);
    my $err = RRDs::error;
    warn "Error while creating graph: $err\n" if $err;
  };

  my $toTimestamp = "UNIX_TIMESTAMP(CONCAT(date,' ',time))";
  # Zjistit dokdy mame data v SQL
  my $sql = "SELECT $toTimestamp AS timestamp FROM sucrom WHERE $filter ORDER BY timestamp DESC LIMIT 1";
  my $sth = $dbh->prepare($sql);
  if ($sth->execute) {
    my $row = $sth->fetchrow_hashref;
    $stop = $row->{timestamp};
  };

  return undef unless (defined($start));
  return undef unless (defined($stop));

  # Pokud je v mysql neco noveho tak to narvat do rrd
  if ($start < $stop) {
    my $start_date = strftime("%Y-%m-%d", localtime($start));
    my $sql = "SELECT UNIX_TIMESTAMP(CONCAT(date, ' 0:00:00')) AS timestamp, count(*) AS count FROM sucrom WHERE '$start_date'<date AND $filter GROUP BY date ORDER BY timestamp";
    my $sth = $dbh->prepare($sql);
    if ($sth->execute) {
      while (my $row = $sth->fetchrow_hashref) {
	for(my $i = 0; $i < 24; $i++) {
	  my $data = ($row->{timestamp}+$i*3600).":".$row->{count};
	  RRDs::update("$db", $data);
	  my $err = RRDs::error;
	  warn "Error while creating graph: $err\n" if $err;
	};
      };
    };
  };

  # Nakresleni grafu
  my $counter = 0;

  foreach my $days (keys %days) {
    my $now = UnixDate(ParseDate('now'), "%d.%m.%Y %H\\\:%M\\\:%S");
    my $stop = time;
    my $start = $stop-$days*24*60*60;
    RRDs::graph("$fb-$days.png",
		#"-z",
		"-i",
		"--start=$start",
		"--end=$stop",
		'-l 0',
		"-t Number of users using eduroam in last ".$days{$days},
		"--width=650",
		"--height=200",
		"--color=BACK#ffffff",
		"--color=SHADEA#ffffff",
		"--color=SHADEB#ffffff",
		"--color=CANVAS#ffffff",
		"--color=MGRID#777777",
		"--color=FONT#074a87",
		"--color=FRAME#074a87",
		"--color=ARROW#074a87",
		"DEF:v_max=$db:value:MAX",
		"DEF:v_avg=$db:value:AVERAGE",
		"DEF:v_min=$db:value:MIN",
		"CDEF:vmax=v_max,UN,0,v_max,IF",
		"CDEF:vavg=v_avg,UN,0,v_avg,IF",
		"CDEF:vmin=v_min,UN,0,v_min,IF",
		"LINE2:vmax\#074a87:Number of users using eduroam",
		'GPRINT:vmin:MIN:min=%.1lf',
		'GPRINT:vavg:AVERAGE:avg=%.1lf',
		'GPRINT:vmax:MAX:max=%.1lf\l',
		'COMMENT:                                                                                           '.$now,
	       );
    my $err = RRDs::error;
    die "Error while creating graph: $err\n" if $err;
  };

  return 1;
};

sub loadLogFile {
  my $dbh = shift;
  my $conn = shift;
  my $file = shift;
  my $servers = shift;
  my $testingID = shift;

  my $ignoreIP = {
		  '195.178.64.172' => 1,  # saint.cesnet.cz
		  '195.113.134.138' => 1, # semik.cesnet.cz
		  '195.113.187.33' => 1,  # ermon.cesnet.cz
		 };
  my $renameIP = {
		  '195.113.44.30' => '195.113.15.22',    # ajias01.jinonice.cuni.cz => radius1.eduroam.cuni.cz
		  '147.32.192.131' => '147.32.192.57',   # orech.feld.cvut.cz => peu1.feld.cvut.cz
		  '195.113.116.5' => '195.113.115.169',  # lisa.faf.cuni.cz => radius1.hknet.cz
		  '195.113.116.7' => '195.113.115.169',  # lisa.faf.cuni.cz => radius1.hknet.cz
		  '147.33.86.10' => '147.33.1.16',       # radius.vscht.cz
		  '146.102.168.6' => '146.102.162.162',  # radius2.vse.cz
		  '147.251.6.40' => '195.113.156.203',   # radius2.cesnet.cz
		  '195.113.2.224' => '195.113.63.66',    # radius.ujop.cuni.cz
		  '195.113.118.5' => '195.113.118.38'    # radius1.uhk.cz
		 };

  my $anonymCache;
  my $proxyCache;
  my $proxyRealmsCache;
  my $realmCache;
  my $csidCache;
  my $nasIDCache;
  my $nasIPCache;

  # Syslog neloguje rok - tudiz ho musime vylovit z data na failu
  my $year;
  if ($file =~ /(\d{4})-\d{2}-\d{2}(|\.log|\.bz2|\.lzma)$/) {
    $year = $1;
  } else {
    die "Unable to get year from filename=\"$file\".\n";
  };

  if ($file =~ /bz2$/) {
    open(FILE, "bzcat $file| ") or die "Can't read \"$file\": $?";
  } elsif ($file =~ /lzma$/) {
    open(FILE, "lzcat $file| ") or die "Can't read \"$file\": $?";
  } else {
    open(FILE, "<$file") or die "Can't read \"$file\": $?";
  };
  while (my $line = <FILE>) {
    chomp($line);

    # Feb 15 11:37:08 radius1 radiator[21012]: access-accept for ST14098@upce.cz (User-Name=) at Proxy=195.113.118.5 (CSID=0012.f0eb.ebb1 NAS=AP04/192.168.13.13)
    if ($line =~ /^(\w+\s+\d+ \d{2}:\d{2}:\d{2}) \S+ radiator\[\d+\]: (access-.+) for (.+) \((User-Name=)(.*)\) at Proxy=([0-9\.]+) \(CSID=(.*) NAS=(.*)\/(.*)\)(.*)$/ ){
      my $time = $1;
      my $code = $2;
      my $outerID = $3;
      my $innerID = $5;
      my $proxyIP = $6;
      my $CSID = $7;
      my $NASID = $8;
      my $NASIP = $9;

      my $endOfLine = $10;
      my $EAP = 0;
      $EAP = 1 if ($endOfLine =~ /EAP=\S+/);

      next if ($ignoreIP->{$proxyIP});
      $proxyIP = $renameIP->{$proxyIP} if (defined($renameIP->{$proxyIP}));

      if ($servers->{$proxyIP}) {
	my $userID = lc ($outerID || $innerID);
	my $realm = $userID; $realm =~ s/.*@//;
	my $monitoring = defined($testingID->{$userID}) || 0;

	my $anonID = getAnonymousID($dbh, $userID, $anonymCache, 1);
	my $proxyID = getProxyID($dbh, $proxyIP, $proxyCache, 1);
	my $realmsID = getProxyRealmsID($dbh, $servers->{$proxyIP}->{realms}, $proxyRealmsCache, 1);
	my $realmID = getRealmID($dbh, $realm, $realmCache, 1);

	my $csidID = getCSIDID($dbh, $CSID || '', $csidCache, 1);
	my $nasID = getNASID($dbh, $NASID || '', $nasIDCache, 1);
	my $nasIPID = getNASIPID($dbh, $NASIP || '', $nasIPCache, 1);

	my $d = ParseDate("$time $year");
	my $date = UnixDate($d, "%Y-%m-%d");
	my $time = UnixDate($d, "%H:%M:%S");

	my @set;
	push @set, "date=\"$date\"";
	push @set, "time=\"$time\"";
	push @set, "result=\"$code\"";
	push @set, "user=\"$anonID\"";
	push @set, "realm=\"$realmID\"";
	push @set, "monitoring=$monitoring";
	push @set, "proxy=\"$proxyID\"";
	push @set, "proxyrealms=$realmsID";
	push @set, "csid=\"$csidID\"";
	push @set, "nasid=\"$nasID\"";
	push @set, "nasip=\"$nasIPID\"";
	push @set, "EAP=$EAP";

	my $sql = "REPLACE INTO roaming SET ".join(', ', @set);
	unless ($dbh->do($sql)) {
	  warn "Failed to insert: $sql ".$dbh->errstr."\n";
	}
      } elsif ($proxyIP eq '195.113.187.22') {
      } elsif ($proxyIP eq '195.113.187.74') {
      } else {
	warn "Unknown proxy: $proxyIP\n";
      };
    } elsif ($line =~ /radiator\[\d+\]: Unknown reply received in AuthRADIUS for request/) {
    } elsif ($line =~ /radiator\[\d+\]: Server started: Radiator/) {
    } elsif ($line =~ /radiator\[\d+\]: SIGTERM received: stopping/) {
    } elsif ($line =~ /radiator\[\d+\]: Attribute number \d+ \(vendor \d+\) is not defined in your dictionary/) {
    } elsif ($line =~ /radiator\[\d+\]: patchAccounting/) {
    } elsif ($line =~ /radiator\[\d+\]: stripAttrs:/) {
    } elsif ($line =~ /radiator\[\d+\]: dead-realm:/) {
    } elsif ($line =~ /radiator\[\d+\]: AuthRADIUS/) {
    } elsif ($line =~ /radiator\[\d+\]: Access rejected for/) {
    } elsif ($line =~ /radiator\[\d+\]: Invalid reply item Expiration ignored/) {
    } elsif ($line =~ /radiator\[\d+\]: Stream connection to .* failed: Connection refused/) {
    } elsif ($line =~ /radiator\[\d+\]: Unknown reply received in AuthRADSEC for request/) {
    } elsif ($line =~ /radiator\[\d+\]: Invalid reply item Expiration ignored/) {
    } elsif ($line =~ /radiator\[\d+\]: AuthRADSEC: No reply from .* for .*\. Now have \d+ consecutive failures over \d+ seconds. Backing off for \d+ seconds/) {
    } elsif ($line =~ /radiator\[\d+\]: AuthRADSEC could not find a working host to forward to. Ignoring/) {
    } elsif ($line =~ /radiator\[\d+\]: AuthRADSEC: No reply from/) {
    } elsif ($line =~ /radiator\[\d+\]: Stream sysread for .* failed.*Peer probably disconnected./) {
    } elsif ($line =~ /radiator\[\d+\]: StreamTLS .* Handshake unsuccessful/) {
    } elsif ($line =~ /radiator\[\d+\]: Duplicate request id .* received/) {
    } elsif ($line =~ /radiator\[\d+\]: patchAccounting: Bad Outer Identity/) {
    } elsif ($line =~ /radiator\[\d+\]: Bad EAP Message-Authenticator/) {
    } elsif ($line =~ /radiator\[\d+\]: Bad authenticator/) {
    } elsif ($line =~ /radiator\[\d+\]: Existing pending request/) {
    } elsif ($line =~ /radiator\[\d+\]: StreamTLS Certificate verification error/) {
    } elsif ($line =~ /radiator\[\d+\]: StreamTLS client error/) {
    } elsif ($line =~ /radiator\[\d+\]: StreamTLS server error/) {
    } elsif ($line =~ /radiator\[\d+\]: Stream connection to .* failed: No route to host/) {
    } elsif ($line =~ /radiator\[\d+\]: Verification of certificate presented by .* failed/) {
    } elsif ($line =~ /radiator\[\d+\]: host2realm/) {
    } elsif ($line =~ /radiator\[\d+\]: AuthRADSEC .* is responding again/) {
    } elsif ($line =~ /radiator\[\d+\]: .*Connection reset by peer/) {
    } elsif ($line =~ /radiator\[\d+\]: .*is not defined in your dictionary/) {
    } elsif ($line =~ /radiator\[\d+\]: Using Net::SSLeay.*/) {
    } elsif ($line =~ /radiator\[\d+\]: sendTo: send to \S+ failed: Invalid argument/) {
    } elsif ($line =~ /radiator\[\d+\]: Malformed Vendor Specific Attribute/) {
    } elsif ($line =~ /radiator\[\d+\]: .*at radius1.eduroam.cz$/) {
    } elsif ($line =~ /radiator\[\d+\]: access-reject for/) {
    } elsif ($line =~ /radiator\[\d+\]: Stream write error, disconnecting: Broken pipe/) {
    } else {
      warn "Unmatched line: $line\n";
    };
  };
};


my $config = AppConfig->new
  ({
    GLOBAL=> { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE => 1
   },
   CFGFilename       => {DEFAULT => './roaming_stats.cfg'},
   LDAPServer        => {DEFAULT => 'localhost'},
   LDAPServerPort    => {DEFAULT => LDAP_PORT},
   LDAPUseSSL        => {DEFAULT => undef},
   LDAPBindDN        => {DEFAULT => ''},
   LDAPBindPassword  => {DEFAULT => ''},
   LDAPTestingIDBase => {DEFAULT => ''},
   LDAPRealmsBase    => {DEFAULT => ''},
   LDAPServersBase   => {DEFAULT => ''},
   MySQLServer       => {DEFAULT => ''},
   MySQLDatabase     => {DEFAULT => ''},
   MySQLUser         => {DEFAULT => ''},
   MySQLPassword     => {DEFAULT => ''},
   RRDDir            => {DEFAULT => ''},
   LogFile           => {DEFAULT => undef},
   RebuildGraphs     => {DEFAULT => undef},
   ReagregateAll     => {DEFAULT => undef},
  );
$config->args(\@ARGV) or
  die "Can't parse cmdline args";
$config->file($config->CFGFilename) or
  die "Can't open config file \"".$config->CFGFilename."\": $!";

my $dbh = DBI->connect('DBI:mysql:database='.$config->MySQLDatabase.':host='.$config->MySQLServer,
		       $config->MySQLUser, $config->MySQLPassword) or
  die "Can't connect to DB";
$dbh->{mysql_auto_reconnect} = 1;


my $ldapConnCFG = {"host"   => $config->LDAPServer,
		   "port"   => $config->LDAPServerPort,
		   "bind"   => $config->LDAPBindDN,
		   "pswd"   => $config->LDAPBindPassword};
$ldapConnCFG->{certdb} = 1 if ($config->LDAPUseSSL>0);
my $conn = new myPerlLDAP::conn($ldapConnCFG) or die "Can't connect to LDAP";

my $servers = getIP2ServerName($conn, $config->LDAPServersBase);
$servers->{'192.87.106.34'} = {
			       name => 'etlr1',
			       realms => 'TOPLEVEL',
			      };
$servers->{'130.225.242.109'} = {
				 name => 'etlr2',
				 realms => 'TOPLEVEL',
				};

my $testingID = getTestingAccounts($conn, $config->LDAPRealmsBase, $config->LDAPTestingIDBase);
$testingID->{'jan@guest.showcase.surfnet.nl'}->{id} = 'jan@guest.showcase.surfnet.nl';

if ($config->LogFile) {
  my $date;
  if ($config->LogFile =~ /(\d{4}-\d{2}-\d{2})(|\.log|\.bz2|\.lzma)$/) {
    $date = $1; $date =~ s/_/\-/g;
  } else {
    die "Unable to get date from filename=\"".$config->LogFile."\" (2).\n";
  };

  loadLogFile($dbh, $conn, $config->LogFile, $servers, $testingID);
  aggregateDate($dbh, $date);
};

reagregateAll($dbh) if ($config->ReagregateAll);

if ($config->RebuildGraphs) {
  my %realms;
  my %rIDCache;
  foreach my $IP (keys %{$servers}) {
    $realms{$servers->{$IP}->{realms}}++;
  };

  my $index = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<html>
  <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-2\">
     <title>Roaming stats</title>
  </head>
<body>\n";

  foreach my $r ('all', sort keys %realms) {
    next if ($r eq '');

    my $rID = 'all';
    $rID = getProxyRealmsID($dbh, $r, \%rIDCache) unless ($r eq 'all');
    if ($rID) {
      if (buildGraph($dbh, $config, $rID)) {
	my $html = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<html>
  <head>
     <meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-2\">
     <title>Roaming stats for locality \"$r\"</title>
  </head>
<body>
<h1>Roaming stats for locality \"$r\"</h1>
<p>\n";
	$index .= "<h1>Locality: $r</h1>\n";
	foreach my $days (sort {$a <=> $b} keys %days) {
	  if (-f $config->RRDDir."/$rID-$days.png") {
 	    $html .= "<p><img src=\"$rID-$days.png\"/></p>\n";
 	    $index .= "<a href=\"$rID.html\"><img border=\"0\" src=\"$rID-$days.png\"/></a>\n" if ($days == 370);
	  };
	};
	$html .= "</p>
</body>
</html>\n";
	my $fname = $config->RRDDir."/$rID.html";
	
	open(HTML, ">$fname");
	print HTML $html;
	close(HTML);
      };
    };
  };

  $index .= "</body>
</html>\n";

  open(INDEX, ">".$config->RRDDir."/index.html");
  print INDEX $index;
  close(INDEX);
};
