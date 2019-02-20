#!/usr/bin/perl

use strict;
use Data::Dumper;
use Text::Iconv;
use AppConfig qw(:expand :argcount);
use myPerlLDAP::utils qw(:all);
#use perlOpenLDAP::API qw(ldap_explode_dn
#			 LDAP_PORT LDAPS_PORT
#			 LDAP_SCOPE_SUBTREE LDAP_SCOPE_ONELEVEL);
use myPerlLDAP::conn;

sub get_organization {
  my $entry = shift;

  my $oPointer = $entry->getValues('oPointer')->[0];
  if (defined($oPointer)) {
    my $organization = $entry->owner->read($oPointer);
    return $organization;
  } else {
    return;
  };
};

sub create_id {
  my $entry = shift;
  my $org = shift;

  if (defined($org)) {
    my $dc = $org->getValues('dc')->[0];
    $dc =~ s/ /_/g;
    return $dc;
  } else {
    my $realm = $entry->getValues('cn')->[0];
    $realm =~ s/\./_/g;
    return $realm;
  };
};

sub get_institution_xml {
  my $entry = shift;

  foreach my $labeled_uri (@{$entry->getValues('labeledURI')}) {
    if ($labeled_uri =~ /^(.+)\s+institution\.xml$/) {
      my $url = $1;
      $url =~ s/~/\%7E/g;
      return $url;
    };
  };

  return;
};

sub get_institution_parent {
  my $realm = shift;
  my $organization = shift;

  my $oParent;
  if (defined($realm)) {
    my $oParentPointer = $realm->getValues('oParentPointer')->[0];
    $oParent = $realm->owner->read($oParentPointer) if (defined($oParentPointer));
    return $oParent if defined($oParent);
  };

  if (defined($organization)) {
    my $oParentPointer = $organization->getValues('oParentPointer')->[0];
    $oParent = $organization->owner->read($oParentPointer) if (defined($oParentPointer));
    return $oParent if defined($oParent);
  };

  return ;
};

sub get_institution_parent_ID {
  my $inst = shift;

  return unless($inst);

  my $dc = $inst->getValues('dc')->[0];
  $dc =~ s/ /_/g;
  return $dc;
};

sub get_entry_string {
  my $entry = shift;
  my $attrs = shift;
  my $lang  = shift;

  return unless ($entry);

  foreach my $attr (@{$attrs}) {
    foreach my $l (@{$lang}, undef) {
      my $lang = 'lang-'.$l if defined($l);
      my $value = $entry->getValues($attr, $lang)->[0];
      return $value if defined($value);
    };
  };

  return;
};

sub create_inst_xml {
  my $realm = shift;
  my $inst = shift;
  my $inst_parent = shift;

  return unless ($realm);
  return unless ($inst);

  my $res= "<?xml version=\"1.0\" encoding=\"iso-8859-2\"?>
<!-- dokumentace k tomuto dokumentu je na strance: http://www.eduroam.cz/doku.php?id=cs:spravce:edudb:institution_xml -->
<institutions>
  <institution>
    <country>cz</country>
       <type>3</type>
       <!-- v pripade ze instituce pouziva vice nez jeden realm tak je nutne uvest vsechny, v tom pripade zduplikujte element inst_realm -->\n";
  foreach my $realm (@{$realm->getValues('cn')}) {
    $res .= "       <inst_realm>$realm</inst_realm>\n";
  };
  $res .= "       <!--jmeno instituce uvadejte kompletni a v obou jazykovych verzich-->
       <org_name lang=\"cs\">".get_entry_string($inst, ['o'], ['cs'])."</org_name>
       <org_name lang=\"en\">".get_entry_string($inst, ['o'], ['en'])."</org_name>
       <address>
          <street>".get_entry_string($inst, ['street'])."</street>
          <city>".get_entry_string($inst, ['l'])."</city>
       </address>\n";
  foreach my $admin_dn (@{$realm->getValues('manager')}) {
    my $admin = $realm->owner->read($admin_dn);
    $res .= "       <contact>
          <name>".$admin->getValues('cn')->[0]."</name>
          <email>".$admin->getValues('mail')->[0]."</email>
          <phone>".$admin->getValues('telephoneNumber')->[0]."</phone>
       </contact>\n";
  };

  $res .= "       <info_URL lang=\"en\">http://doplnit-url.cz/en/procizi/index.html</info_URL>
       <info_URL lang=\"cs\">http://doplnit-url.cz/cz/procizi/index.html</info_URL>
       <policy_URL lang=\"cs\">http://www.eduroam.cz/doku.php?id=cs:roamingova_politika</policy_URL>

       <!-- casova znacka, mela by se zmenit pri kazde zmene dokumentu -->
       <ts>2008-04-18T11:35:00</ts>

       <location>
          <longitude>14°10'52.946\"E</longitude>
          <latitude>49°36'16.507\"N</latitude>
          <!--loc_name lang=\"en\">volitelny nazev loklaity pro pripady ze adresa nestaci</loc_name-->
          <address>
            <street>".get_entry_string($inst, ['street'])."</street>
            <city>".get_entry_string($inst, ['l'])."</city>
          </address>
          <SSID>eduroam</SSID>
          <enc_level>WPA + AES, TKIP</enc_level>
          <port_restrict>true</port_restrict>
          <transp_proxy>false</transp_proxy>
          <IPv6>false</IPv6>
          <NAT>false</NAT>
          <!-- pocet AP. Volitelne -->
          <!-- AP_no>0</AP_no -->
          <wired>false</wired>
          <info_URL lang=\"en\">http://doplnit-url.cz/en/procizi/index.html</info_URL>
          <info_URL lang=\"cs\">http://doplnit-url.cz/cz/procizi/index.html</info_URL>
       </location>
  </institution>
</institutions>
";


};

my $config = AppConfig->new
  ({
    GLOBAL=> { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE => 1
   },
   CFGFilename            => {DEFAULT => './edudb-buildConfig.cfg'},

   LDAPServer             => {DEFAULT => 'localhost'},
   LDAPServerPort         => {DEFAULT => LDAP_PORT},
   UseSSL                 => {DEFAULT => 0},
   BindDN                 => {DEFAULT => 'uid=semik,ou=People,o=test'},
   BindPassword           => {DEFAULT => 'test_password'},
   SearchBase             => {DEFAULT => 'ou=o=test'},
   Output                 => {DEFAULT => "-"},
  );

$config->args(\@ARGV) or die "Can't parse cmdline args";
$config->file($config->CFGFilename) or die "Can't open config file \"".$config->CFGFilename."\": $!";

# -- Pripojeni k LDAPu ---------------------------------------------------------
my $conn = new myPerlLDAP::conn({"host"   => $config->LDAPServer,
				 "port"   => $config->LDAPServerPort,
				 "bind"   => $config->BindDN,
				 "pswd"   => $config->BindPassword,
				 "certdb" => 1}) or
  die "Can't create myPerlLDAP::conn object";


my $sres = $conn->search($config->SearchBase,
			 LDAP_SCOPE_SUBTREE,
			 '(&(objectClass=eduRoamRealm)(eduroamConnectionStatus=connected))')
    or die "Can't search: ".$conn->errorMessage;

$sres->sort('cn');

my $cfg = '';

my %k_inst;
my %k_inst_parent;

while (my $realm = $sres->nextEntry) {
  my $organization = get_organization($realm);
  my $ID = create_id($realm, $organization);
#  my $inst_xml = get_institution_xml($realm);
  my $inst_parent = get_institution_parent($realm, $organization);
  my $inst_parent_id = get_institution_parent_ID($inst_parent);
  my $org_name_cs = get_entry_string($organization, ['o'], ['cs']);
  my $org_name_en = get_entry_string($organization, ['o'], ['en']);
  my $org_unit_name_cs = get_entry_string($organization, ['ou'], ['cs']);
  my $org_unit_name_en = get_entry_string($organization, ['ou'], ['en']);
  my $acronym_cs = get_entry_string($organization, ['oAbbrev'], ['cs']);
  my $acronym_en = get_entry_string($organization, ['oAbbrev'], ['en']);
  my $acronym_unit_cs = get_entry_string($organization, ['ouAbbrev'], ['cs']);
  my $acronym_unit_en = get_entry_string($organization, ['ouAbbrev'], ['en']);

#  if (defined($organization) and not (defined($inst_xml))) {
#    my $r = $realm->getValues('cn')->[0];
#    `mkdir -p /tmp/edudb/$r`;
#    open(INST, ">/tmp/edudb/$r/institution.xml");
#    print INST create_inst_xml($realm, $organization, $inst_parent);
#    close(INST);
#  };

#  next unless (defined($inst_xml));

  # Poznamenat zname instituce
  $k_inst{$organization->dn} = $organization if defined($organization);
  # Poznamenat zname rodicovske organizace;
  $k_inst_parent{$inst_parent->dn} = $inst_parent if defined ($inst_parent);

  $cfg .= "# ".$realm->dn."\n";
  $cfg .= "[$ID]
realm = ".join(', ', @{$realm->getValues('cn')})."\n";
#  $cfg .= "institution_xml = $inst_xml\n" if defined($inst_xml);
  $cfg .= "parent = $inst_parent_id\n" if defined($inst_parent_id);
  $cfg .= "org_name_en = $org_name_en\n" if defined($org_name_cs);
  $cfg .= "org_name_cs = $org_name_cs\n" if defined($org_name_cs);
  $cfg .= "org_unit_name_en = $org_unit_name_en\n" if defined($org_unit_name_cs);
  $cfg .= "org_unit_name_cs = $org_unit_name_cs\n" if defined($org_unit_name_cs);
  $cfg .= "acronym_en = $acronym_en\n" if defined($acronym_cs);
  $cfg .= "acronym_cs = $acronym_cs\n" if defined($acronym_cs);
  $cfg .= "acronymunit_en = $acronym_unit_en\n" if defined($acronym_unit_cs);
  $cfg .= "acronymunit_cs = $acronym_unit_cs\n" if defined($acronym_unit_cs);
  $cfg .= "\n";
};

# Zkontrolovat jestli vsechny rodicovske instituce jsou nadefinovany v
# konfiguraku.

foreach my $inst_parent_dn (sort keys %k_inst_parent) {
  next if (defined($k_inst{$inst_parent_dn}));
  next if ($inst_parent_dn eq '');

  my $organization = $k_inst_parent{$inst_parent_dn};

  my $ID = create_id(undef, $organization);
  my $org_name_cs = get_entry_string($organization, ['o'], ['cs']);
  my $org_name_en = get_entry_string($organization, ['o'], ['en']);
  my $acronym_cs = get_entry_string($organization, ['oAbbrev'], ['cs']);
  my $acronym_en = get_entry_string($organization, ['oAbbrev'], ['en']);

  $cfg .= "#$inst_parent_dn\n";
  $cfg .= "[$ID]\n";
  $cfg .= "org_name_en = $org_name_en\n" if defined($org_name_cs);
  $cfg .= "org_name_cs = $org_name_cs\n" if defined($org_name_cs);
  $cfg .= "acronym_en = $acronym_en\n" if defined($acronym_cs);
  $cfg .= "acronym_cs = $acronym_cs\n" if defined($acronym_cs);
  $cfg .= "\n";
};

#print "DEBUG = 0
#LOG_STDOUT = 0
#CACHE_DIR = /tmp/edudb
#CONF_ENCODING = utf8
#\n\n";

print $cfg;






# Instituce 16. 12. 2008
#http://eduroam.cesnet.cz/instituce/amu.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/asuch.cas.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/czu.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/fm.vse.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/fpf.slu.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/fsv.cvut.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/fzu.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/htf.cuni.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/jmnet.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/kr-vysocina.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/lf3.cuni.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/lfhk.cuni.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/lfmotol.cuni.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/natur.cuni.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/tul.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/uhk.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/upol.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/vc.cvut.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/vfn.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/vfu.cz/institution.xml
#http://eduroam.cesnet.cz/instituce/vscht.cz/institution.xml
