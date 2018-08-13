#!/usr/bin/perl -w

use strict;
use perlOpenLDAP::API qw(LDAP_PORT LDAPS_PORT LDAP_SCOPE_SUBTREE LDAP_SCOPE_ONELEVEL);
use myPerlLDAP::conn;
use XML::LibXML;
use XML::Tidy;
use DBI;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Encode qw(encode_utf8);
use AppConfig qw(:expand);
use POSIX qw(strftime);
use myForms::utils qw(toUTF8 toASCII toIL2);

use lib qw(../../ermon);
use lib::DNS;

my $max_age = `date "+%Y-%m-01" -d '6 months ago'`; chomp($max_age);

my $config = AppConfig->new
  ({
    GLOBAL=> { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE => 1
   },
   CFGFilename       => {DEFAULT => './edudb.cfg'},
   LDAPServer        => {DEFAULT => 'localhost'},
   LDAPServerPort    => {DEFAULT => LDAP_PORT},
   LDAPUseSSL        => {DEFAULT => undef},
   LDAPBindDN        => {DEFAULT => ''},
   LDAPBindPassword  => {DEFAULT => ''},
   LDAPRealmsBase    => {DEFAULT => ''},
   LDAPServersBase   => {DEFAULT => ''},
   MySQLServer       => {DEFAULT => ''},
   MySQLDatabase     => {DEFAULT => ''},
   MySQLUser         => {DEFAULT => ''},
   MySQLPassword     => {DEFAULT => ''},
   PublishDirectory  => {DEFAULT => ''},
  );

sub add_element {
  my $doc = shift;
  my $element = shift;
  my $name = shift;
  my $value = shift;

  my $ae = $doc->createElement($name);
  $element->appendChild($ae);
  if (defined($value)) {
    my $ae_value = $doc->createTextNode($value);
    $ae->appendChild($ae_value);
  };

  return $ae;
};


sub updateXML {
  my $doc = shift;
  my $filename = shift;
  my $tidy = shift;

  my $xml = $doc->toString;

  if ($tidy) {
    my $tidyObj = XML::Tidy->new(xml => $xml);
    $xml = "<?xml version=\"1.0\" encoding=\"".$doc->getEncoding."\"?>\n".$tidyObj->tidy->toString;
  };

#  if (-f $filename) {
#    my $xmlMD5 = md5_hex(encode_utf8($xml));
#    open(XML, "<$filename") or
#      die "Can't open file \"$filename\" for reading: $!";
#    my $ctx = Digest::MD5->new; $ctx->addfile(*XML);
#    my $xmlFileMD5 = $ctx->hexdigest;
#    close(XML) or
#      die "Can't close file \"$filename\": $!";

#    if ($xmlMD5 ne $xmlFileMD5) {
#      print STDERR "XML File changed! Updating: $filename\n";
#      #`cp $cfgPath $cfgPath-$date`;
#    } else {
#      return 1;
#    };
#  } else {
#    print STDERR "XML File \"$filename\" not found. Creating.\n";
#  };

  open (XML, ">$filename") or
    die "Can't open file \"$filename\" for writting: $!";

  warn "$filename";

  print XML encode_utf8($xml) or
    die "Can't write into file \"$filename\": $!";
  close (XML) or
    die "Can't close file \"$filename\": $!";

  return 1;
};

sub usage {
  my $dbh = shift;
  my $org2radius = shift;

  my $doc_inst_usage = XML::LibXML::Document->createDocument( '1.0', 'iso-8859-2' );
  my $inst_usages = $doc_inst_usage->createElement('institution_usages');
  $doc_inst_usage->setDocumentElement($inst_usages);

  my %realm_data;

  foreach my $org (keys %{$org2radius}) {
    warn "Garthering data about: $org ...\n";
    my @radius_ip;

    foreach my $radius (keys %{$org2radius->{$org}}) {
      next unless (my $IP = lib::DNS::getIP($radius));
      push @radius_ip, $IP;
    };

    next unless @radius_ip;

    my $sql = "SELECT date, count(*) FROM roaming AS ROAM, user AS U, proxy AS P, realm AS R WHERE ROAM.date>='$max_age' AND ROAM.user=U.id AND ROAM.realm=R.id AND ROAM.proxy=P.id AND ROAM.result='access-accept' AND ROAM.monitoring=0 AND (".join(' OR ', map {"P.proxy='$_'"} @radius_ip).") AND \%s GROUP BY ROAM.date";

    my $national = sprintf($sql, "R.realm LIKE '%cz'");
    my $international = sprintf($sql, "NOT R.realm LIKE '%cz'");

    my %data;
    my $sth = $dbh->prepare($national);
    if ($sth->execute) {
      foreach my $d (@{$sth->fetchall_arrayref}) {
	$data{$d->[0]}->{national} = $d->[1];
	$realm_data{$d->[0]}->{national} += $d->[1];
      };
    };

    $sth = $dbh->prepare($international);
    if ($sth->execute) {
      foreach my $d (@{$sth->fetchall_arrayref}) {
	$data{$d->[0]}->{international} = $d->[1];
	$realm_data{$d->[0]}->{international} += $d->[1];
      };
    };

    if (%data) {
      my $inst_usage = add_element($doc_inst_usage, $inst_usages, 'institution_usage');
      $inst_usage->setAttribute('inst_realm', $org);

      foreach my $date (sort keys %data) {
	my $usage = add_element($doc_inst_usage, $inst_usage, 'usage');
	$usage->setAttribute('date', $date);
	#add_element($doc_inst_usage, $usage, 'local_sn', -666);
	add_element($doc_inst_usage, $usage, 'national_sn', $data{$date}->{national} || 0);
	add_element($doc_inst_usage, $usage, 'international_sn', $data{$date}->{international} || 0);
      };
    };
  };

  my $doc_realm_usage = XML::LibXML::Document->createDocument( '1.0', 'iso-8859-2' );
  my $realm_usages = $doc_realm_usage->createElement('realm_usages');
  $doc_realm_usage->setDocumentElement($realm_usages);

  my $realm_usage = add_element($doc_realm_usage, $realm_usages, 'realm_usage');
  $realm_usage->setAttribute('country', 'cz');

  foreach my $date (sort keys %realm_data) {
    my $usage = add_element($doc_realm_usage, $realm_usage, 'usage');
    $usage->setAttribute('date', $date);
    add_element($doc_realm_usage, $usage, 'national_sn', $realm_data{$date}->{national} || 0);
    add_element($doc_realm_usage, $usage, 'international_sn', $realm_data{$date}->{international} || 0);
  };

  return ($doc_inst_usage, $doc_realm_usage);
};

sub realm_data {
  my $conn = shift;

  my $doc_realm_data = XML::LibXML::Document->createDocument( '1.0', 'iso-8859-2' );
  my $realm_data_root = $doc_realm_data->createElement('realm_data_root');
  $doc_realm_data->setDocumentElement($realm_data_root);

  my $realm_data = add_element($doc_realm_data, $realm_data_root, 'realm_data');
  add_element($doc_realm_data, $realm_data, 'country', 'cz');

  my $sres = $conn->search($config->LDAPRealmsBase,
			   LDAP_SCOPE_ONELEVEL,
			   '(objectClass=eduRoamRealm)')
  or die "Can't search: ".$conn->errorMessage;

  add_element($doc_realm_data, $realm_data, 'number_IdP', $sres->count);
  add_element($doc_realm_data, $realm_data, 'number_SP', $sres->count);
  add_element($doc_realm_data, $realm_data, 'number_SPIdP', $sres->count);
  add_element($doc_realm_data, $realm_data, 'ts', strftime("%Y-%m-%dT%H:%M:%S", localtime));

  return $doc_realm_data;
};


sub global_realm {
  my $doc_realm = XML::LibXML::Document->createDocument( '1.0', 'utf-8' );
  my $realms = $doc_realm->createElement('realms');
  $doc_realm->setDocumentElement($realms);

  my $realm = add_element($doc_realm, $realms, 'realm');

  add_element($doc_realm, $realm, 'country', 'cz');
  add_element($doc_realm, $realm, 'stype', 1);
  my $org_name_en = add_element($doc_realm, $realm, 'org_name', 'CESNET');
  $org_name_en->setAttribute('lang', 'en');
  my $address = add_element($doc_realm, $realm, 'address');
  add_element($doc_realm, $address, 'street', 'Zikova 4');
  add_element($doc_realm, $address, 'city', 'Praha 6');
  my $contact = add_element($doc_realm, $realm, 'contact');
  add_element($doc_realm, $contact, 'name', toUTF8('Jan Tomá¹ek'));
  add_element($doc_realm, $contact, 'email', 'jan.tomasek@cesnet.cz');
  add_element($doc_realm, $contact, 'phone', '+420 2 2435 2994');
  $contact = add_element($doc_realm, $realm, 'contact');
  add_element($doc_realm, $contact, 'name', toUTF8('Jan Fürman'));
  add_element($doc_realm, $contact, 'email', 'jan.furman@cesnet.cz');
  add_element($doc_realm, $contact, 'phone', '+420 2 2435 2994');

  my $info_cz = add_element($doc_realm, $realm, 'info_URL', 'http://www.ces.net/');
  $info_cz->setAttribute('lang', 'en');
  my $info_en = add_element($doc_realm, $realm, 'info_URL', 'http://www.cesnet.cz/');
  $info_en->setAttribute('lang', 'cz');
  my $policy_cz = add_element($doc_realm, $realm, 'policy_URL', 'http://www.eduroam.cz/doku.php?id=cs:roamingova_politika');
  $policy_cz->setAttribute('lang', 'cz');
  add_element($doc_realm, $realm, 'ts', strftime("%Y-%m-%dT%H:%M:%S", localtime));

  return $doc_realm;
};

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

my $org2radius = {};
my $radius2org = {
		  'radius1.eduroam.cuni.cz' => 'cuni.cz',
		  'radius2.eduroam.cuni.cz' => 'cuni.cz',
		 };
my $org2realms = {
		  'cuni.cz' => {
				'cuni.cz' => 0
			       },
		 };

# Realms Entry Cache
my $realms = {};


# Read ALL defined eduroam RADIUS servers, except of those disabled
my $sres = $conn->search($config->LDAPServersBase,
			 LDAP_SCOPE_ONELEVEL,
			 '(&(objectClass=eduroamRadius)(!(radiusDisabled=*))(eduroamInfRealm=*))')
  or die "Can't search: ".$conn->errorMessage;

while (my $radius = $sres->nextEntry) {
  my $hostname = $radius->getValues('cn')->[0];

  foreach my $realm_dn (@{$radius->getValues('eduroamInfRealm')}) {
    my $realm_entry = $realms->{$realm_dn};
    unless ($realm_entry) {
      $realms->{$realm_dn} = $conn->read($realm_dn) or
	die "Failed to read $realm_dn: ".$conn->errorMessage;
      $realm_entry = $realms->{$realm_dn};
    };

    my $org_realm = $radius2org->{$hostname};
    unless ($org_realm) {
      $radius2org->{$hostname} = $realm_entry->getValues('cn')->[0];
      $org_realm = $radius2org->{$hostname};
    };

    foreach my $realm (@{$realm_entry->getValues('cn')}) {
      $org2realms->{$org_realm}->{$realm}++;
    };
  };
};

foreach my $hostname (keys %{$radius2org}) {
  $org2radius->{$radius2org->{$hostname}}->{$hostname}++;
};

my ($institution_usage, $usage) = usage($dbh, $org2radius);
my $realm_data = realm_data($conn);
my $realm = global_realm($conn);

updateXML($institution_usage, $config->PublishDirectory.'/institution_usage.xml', 1);
updateXML($usage, $config->PublishDirectory.'/realm_usage.xml', 1);
updateXML($realm_data, $config->PublishDirectory.'/realm_data.xml', 1);
updateXML($realm, $config->PublishDirectory.'/realm.xml', 1);
