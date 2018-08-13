# function to process confg file

package lib::CONF_SHARED;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&get_realms_from_file fix_czech_sz);

use Sys::Syslog qw(:standard :macros);
use lib::LOG;
use Text::Iconv;
use Data::Dumper;
use Unicode::String qw(utf8 latin1 utf16);


# index to array constants
use constant REALM => 'realm';  # realms
use constant INST_XML => 'inst_xml';  # url to institution.xml
use constant PARENT => 'parent';  # relation to another realm
use constant PATTERN => 'pattern'; # pattern match instead of exact match
use constant ORGNAME => 'org_name'; # institution name
use constant ORGUNITNAME => 'org_unit_name';  # unit of institution name
use constant ACRONYM => 'acronym';  # acronym of institution
use constant ACROUNIT => 'acronymunit';  # acronym of unit of institution
use constant URL => 'url';  # url to description of eduroam at institution
use constant INFO_URL => 'info_URL';  # info url xml element

use constant TO_CODE => 'utf8';  # USE SAME SYNTAX AS FOR $from_code 

### get_realms_from_file reads list of realms and their url with institution.xml

sub detect_realms {
  my $config = shift;
  my $lang = shift;

  my %realms;
 
  # for config variables get realm-id
  # acrounit isn't included because contains ACRONYM too and nothing required follows
  my @detect_cloud = ( REALM, INST_XML, PARENT, PATTERN, ORGNAME, ORGUNITNAME, ACRONYM, URL );

  for my $detector (@detect_cloud) {
    #print $detector .'\n';
    my $lookfor = '^(.+)_'. $detector ;
    my %res = $config->varlist( $lookfor );
    #print Dumper keys(%res);

    foreach my $key (keys %res) {
      $key =~ $lookfor;
      #print Dumper $1;

      if( defined $realms{ $1 } ) {
        $realms{ $1 }++;
      } else {
        $realms{ $1 } = 1;
      }
    }
  }

  return %realms;
}

### res hash contain array with first member url, orhers are realms
sub get_realms_from_file {
  my $config = shift;
  my $from_code = shift;
  my %res;  # result hash
  my @tmp;  # temporary result
  my $row;

  # create iconv
	my $to_code = TO_CODE;
  my $converter = Text::Iconv->new($from_code, $to_code);

  # lookfor available languages in config
  my @langs = split( ',', $config->get( 'LANG' ));
  chomp( @langs );

  my %varlist = detect_realms( $config, $langs[0] );

  # list of realm
  #my %varlist = $config->varlist('^.+_'. $config->REALM_RECORD . $langs[0].'$');
  foreach my $varname (keys %varlist)
  {
    #log_it( LOG_DEBUG, "get_realms_from_file(): Variable name $varname, value = ". $config->get($varname));

    my %realm_hash;

    # get realm_id
    #print $varname ."\n";
    #my $lookfor = '^(.+)_'. $config->REALM_RECORD . $langs[0] .'$';
    #$varname =~ /$lookfor/;
    my $realm_id = $varname;
    my $log_mess = "get_realms_from_file(): Realm-id : ". $realm_id ." ";

    # get admitted realms
		if (defined $config->get($realm_id.'_realm')) {
      my @realms = split(' *, *', $config->get($realm_id.'_realm'));
      chomp( @realms );

      $realm_hash{REALM} = \@realms;
		}

    # foreach realm try to search others variables
    my @instxmllist = $config->varlist('^'.$realm_id.'_institution_xml');
    $realm_hash{INST_XML} = $config->get( $instxmllist[0] ) if defined $instxmllist[0];
    $log_mess .= "/ url : ". $realm_hash{INST_XML} if defined $instxmllist[0];

    my @patternlist = $config->varlist( '^'.$realm_id.'_pattern');
    $realm_hash{PATTERN} = $config->get( $patternlist[0] ) if defined $patternlist[0];
    $log_mess .= "/ pattern ". $realm_hash{PATTERN} if defined $realm_hash{PATTERN};
    log_it( LOG_DEBUG, $log_mess);

    # it can have parent
    my @parentlist = $config->varlist('^'.$realm_id.'_parent');
    $realm_hash{PARENT} = $config->get( $parentlist[0] ) if defined $parentlist[0];

    # url to web of eduroam of institution
    my @urllist = $config->varlist('^'.$realm_id.'_url');
    $realm_hash{URL} = $config->get( $urllist[0] ) if defined $urllist[0];

    # international options in available languages
    # orgname,orgunitname,acronym,acrounit
    foreach my $lang (@langs) {
	    # orgname
      my @orgnamelist = $config->varlist('^'.$realm_id.'_'. ORGNAME .'_'.$lang);
      $realm_hash{ ORGNAME."_".$lang } = utf8( $converter->convert( $config->get(  $orgnamelist[0] ) )) if defined $orgnamelist[0];
			#$realm_hash{ ORGNAME."_".$lang } = utf8(                    ( $config->get(  $orgnamelist[0] ) )) if defined $orgnamelist[0];

      #orgnameunit
      my @orgnameunitlist = $config->varlist('^'.$realm_id.'_'.ORGUNITNAME.'_'.$lang);
      $realm_hash{ ORGUNITNAME."_".$lang } = utf8( $converter->convert( $config->get(  $orgnameunitlist[0] ))) if defined $orgnameunitlist[0];

      # acronym
      my @acronymlist = $config->varlist('^'.$realm_id.'_acronym_'.$lang);
      $realm_hash{ ACRONYM."_".$lang } = utf8( $converter->convert( $config->get(  $acronymlist[0] ))) if defined $acronymlist[0];

      # acronymunit
      my @acrounitlist = $config->varlist('^'.$realm_id.'_acronymunit_'.$lang);
      $realm_hash{ ACROUNIT."_".$lang } = utf8( $converter->convert( $config->get( $acrounitlist[0] )) ) if defined $acrounitlist[0];
		
    }

    $res{$realm_id} = \%realm_hash;


  }

  return %res;
}

sub fix_czech_sz {
  my $doc = shift;

  foreach my $tag ('org_name', 'info_URL', 'policy_URL', 'loc_name') {
    foreach my $node (@{$doc->getElementsByTagName($tag)}) {
      if ($node->getAttribute('lang') eq 'cz') {
	$node->setAttribute('lang', 'cs');
      };
    };
  };
};


1;
