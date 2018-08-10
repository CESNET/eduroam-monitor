#!/usr/bin/perl

use strict;
use RRDs;
use POSIX;
use Proc::ProcessTable;
use Date::Manip;
use Data::Dumper;

$| = 1;

# Jan 17 05:45:39 radius1 racoon: INFO: @(#)ipsec-tools 0.6.5 (http://ipsec-tools.sourceforge.net)

my $db = '/var/www/ssl/eps2/radius1edu-racoon/racoon-restarts.rrd';
my $pidFile = "/var/run/racoonRestarts.pl.pid";

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

  RRDs::create("/var/www/ssl/eps2/radius1edu-racoon/racoon-restarts.rrd",
	       "--step=1",
	       "--start=1072911600", # some time in past
	       "DS:restarts:GAUGE:600:0:U",
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

sub update {
  my $db = shift;
  my $time = shift;
  my $value = shift;

#  if ($value) {
#    warn "$time:$value\n";
#  };

  RRDs::update($db,
	       "$time:$value");
  my $err = RRDs::error;
  warn "Error while inserting data graph: $err\n" if $err;
};

sub max {
  my $a = shift;
  my $b = shift;

  return $a if ($a>=$b);
  return $b;
};

sub dataStart {
  my $rrd = shift;

  return time unless -f $rrd;

  my ($start,$step,$names,$data) = RRDs::fetch(
					       $rrd,
					       "MAX",
					       "-s ".`date +"%s" -d "370 days ago"`,
					       "-e ".time,
					      );
  return time unless ($data);
  for (my $i = 0; $i<@{$data}; $i++) {
    warn "i=$i\n";
    warn Dumper($data->[$i]->[0]);
    return $start+$i*$step if (defined($data->[$i]->[0]));
  };

  return time;
};

my %months = (
	   Jan => 0,
	   Feb => 1,
	   Mar => 2,
	   Apr => 3,
	   May => 4,
	   Jun => 5,
	   Jul => 6,
	   Aug => 7,
	   Sep => 8,
	   Oct => 9,
	   Nov =>10,
	   Dec =>11,
	  );

startRun();

#createRRD;

# Zpracovavame data pouze pokud jsou starsi nez 2minuty - to kvuli
# tomu aby jsem nezapsal ze racoon je ok a na dalsim radku zpracovanym
# v jinym behu tohohle skriptu nebylo napsano ze se restartoval.
my $tmago = `date +'%s' -d "2 minutes ago"`; chomp($tmago);
my $startFrom = RRDs::last($db) || 1;

while (my $file = <>) {
  chomp($file);

#  warn "$file\n";
  open(LOG, "<$file");
  my $year = `date +"\%Y"`; chomp($year);
  if ($file =~ /(\d{4})_(\d{2})_(\d{2}).log$/) {
    $year = $1;
  };
  my %data;
  my %k;
  while (my $line = <LOG>) {
    chomp($line);
    # Jan 17 05:45:39 radius1 racoon: INFO: @(#)ipsec-tools 0.6.5 (http://ipsec-tools.sourceforge.net)
    if ($line =~ /^(\w{3})\s+(\d+)\s+(\d{2}):(\d{2}):(\d{2}) radius1(mng1|mng2|) racoon:(.*)$/o) {
      my $month = $1;
      my $day = $2;
      my $hour = $3;
      my $min = $4;
      my $sec = $5;
      my $l = $7;

      my $seconds = POSIX::mktime($sec, $min, $hour, $day, $months{$month}, $year-1900);

      $data{$seconds} += 0;
      if ($l =~ /.*INFO: @\(#\)ipsec-tools/) {
	$data{$seconds}++
      };
    };
  };

  foreach my $sec (sort keys %data) {
#    warn "$sec: $tmago: $startFrom\n";
    if (($sec < $tmago) and ($sec > $startFrom)) {
      update($db, $sec, $data{$sec});
    };
  };
  close(LOG);
};

stopRun();
