# functions for logging

package lib::LOG;

use strict;
use Sys::Syslog qw(:standard :macros);
use String::Escape qw(printable unprintable);
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&log_set_option &log_begin &log_close &log_die &log_it);

my $lib_to_syslog = 0;
my $lib_to_stdout = 0;
my $lib_log_level = 0;

### set logging options
sub log_set_option {
  my $to_syslog = shift;
  my $to_stdout = shift;
  my $log_level = shift;

  $lib_to_syslog = $to_syslog;
  $lib_to_stdout = $to_stdout;
  $lib_log_level = $log_level;
}

### openlog and setmask
sub log_begin {
  my $program = shift;
  my $opts = shift;
  my $facility = shift;
  my $level = shift;
  my $to_syslog = shift;
  my $to_stdout = shift;

  openlog( $program, $opts, $facility );

  setlogmask( Sys::Syslog::LOG_UPTO( $level ) );

  log_set_option( $to_syslog, $to_stdout, $level );
}

### close log
sub log_close {
  closelog();
}

### log and die (special version of log_it)
sub log_die {
  my $mess = shift;

  syslog( LOG_ERR, printable($mess) ) if $lib_to_syslog;

#  print $mess if $lib_to_stdout;

  log_close();
  die("$mess\n");
}

### log_it logs function
sub log_it {
  my $level = shift;
  my $mess = shift;

  syslog( $level, printable($mess) ) if $lib_to_syslog;

  print $mess ."\n" if (($lib_to_stdout) && ($lib_log_level >= $level ));
}

1;
