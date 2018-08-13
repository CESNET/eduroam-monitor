#!/usr/bin/perl -w

use strict;
use AppConfig qw(:expand);
use POSIX;
use Data::Dumper;
use myPerlLDAP::utils qw(:all);
use myPerlLDAP::conn;
use myPerlLDAP::entry;
use myPerlLDAP::attribute;
use Date::Manip;
use Net::DNS;
use Text::Iconv;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use XML::LibXML;
use Sys::Syslog qw(:standard :macros);
use File::Temp qw(tempfile);

sub _syslog {
  sub escape {
    my $line = shift;

    $line =~ s,\:,\/\:,g;

    return $line;
  };

  openlog('export-eduroam-orgs', 'ndelay,pid', LOG_LOCAL1);
  syslog('info', join(":", map {escape($_)} @_));
  closelog();
};

sub store_to_file {
  my $filename = shift;
  my $content = shift;

  if ( -f $filename ) {
    my $c = $content; utf8::encode($c);
    my $md5_new = md5_hex($c);
    my $cmd = 'md5sum '.$filename.' | sed "s/ .*//"';
    my $old_md5sum = `$cmd`; chomp($old_md5sum);

    # Obsah souboru se nezmenil?
    return if ($md5_new eq $old_md5sum);
  };

  my ($tmp_fh, $tmp_filename) = tempfile("/tmp/export-eduroam-orgs`-XXXXXX");
  binmode $tmp_fh, ":utf8";
  print $tmp_fh $content;
  close($tmp_fh);
  rename($tmp_filename, "$filename") or die "Failed to move $tmp_filename to $filename: $!";
  chmod(0644, "$filename");
};

my $config = AppConfig->new
  ({
    GLOBAL=> { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE => 1
   },
   CFGFilename       => {DEFAULT => './eduroam-seznam.cfg'},
   LDAPServer        => {DEFAULT => 'localhost'},
   LDAPServerPort    => {DEFAULT => LDAPS_PORT},
   UseSSL            => {DEFAULT => undef},
   BindDN            => {DEFAULT => ''},
   BindPassword      => {DEFAULT => ''},
   RealmsBase        => {DEFAULT => ''},
   ExportFile        => {DEFAULT => ''},
  );

my $conn;
$config->args(\@ARGV) or
  die "Can't parse cmdline args";
$config->file($config->CFGFilename) or
  die "Can't open config file \"".$config->CFGFilename."\": $!";

$conn = new myPerlLDAP::conn({"host"   => $config->LDAPServer,
			      "port"   => $config->LDAPServerPort,
			      "bind"   => $config->BindDN,
			      "pswd"   => $config->BindPassword,
			      "certdb" => $config->UseSSL}) or
  die "Can't create myPerlLDAP::conn object";
$conn->init or
  die "Can't open LDAP connection to ".$config->LDAPServer.":".$config->LDAPServerPort.": ".$conn->errorMessage;

my $xml = '<?xml version="1.0"?>
<institutions>
';

my $sres = $conn->search($config->RealmsBase,
			 LDAP_SCOPE_ONE,
			 "(&(cn=*)(labeledURI=*)(oPointer=*))");
while (my $entry = $sres->nextEntry) {
  my $realm = $entry->getValues('cn')->[0];
  my $o_dn = $entry->getValues('oPointer')->[0];
  my $o = $conn->read($o_dn);
  my $cesnet_id = $o->getValues('cesnetOrgID')->[0] || do {
    _syslog("Chybi cesnetOrgID pro $realm.");
    undef;
  };
  if (defined($realm) and defined($cesnet_id)) {
    $xml .= "<institution><inst_realm>$realm</inst_realm><ID>$cesnet_id</ID></institution>\n";
  };
};

$xml .= "</institutions>\n";

store_to_file($config->ExportFile, $xml);
