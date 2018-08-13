# output gpx package

package lib::OUT_GPX;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&out_gpx);

use Tree;
use Sys::Syslog qw(:standard :macros);
use lib::LOG;
use lib::CONF_SHARED;
use lib::OUT_BASE;
use Data::Dumper;
use XML::Tidy;
use locale;
#use Unicode::String qw(utf8 latin1 utf16);

use constant ELEMENT_GPX => 'gpx';
use constant ELEMENT_WPT => 'wpt';
use constant ELEMENT_NAME => 'name';
use constant ELEMENT_DESC => 'desc';
use constant ELEMENT_LINK => 'link';
use constant ATTR_LAT => 'lat';
use constant ATTR_LON => 'lon';
use constant ATTR_HREF => 'href';
use constant ATTR_XMLNS_VALUE => 'http://www.topografix.com/GPX/1/1';
use constant ATTR_XMLNS => 'xmlns';
use constant ATTR_XSI_VALUE => 'http://www.w3.org/2001/XMLSchema-instance';
use constant ATTR_XSI => 'xmlns:xsi';
use constant ATTR_SCHEMA_VALUE => 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd';
use constant ATTR_SCHEMA => 'xsi:schemaLocation';
use constant ATTR_VERSION_VALUE => '1.1';
use constant ATTR_VERSION => 'version';
use constant ATTR_CREATOR_VALUE => 'lib::OUT_GPX.pm';
use constant ATTR_CREATOR => 'creator';

# get element data
#sub get_element_data {
#  my $node = shift;  # where
#  my $element = shift;  # what
#
#  my @res = $node->getElementsByTagName( $element );
#  return $res[0]->getFirstChild->getData if defined $res[0];
#
#  return undef;
#}

# lookfor all location element in particular xml
sub add_org_waypoints {
  my $r_realm = shift;
  my $r_wpts = shift;
  my $root = shift;
	my $type_desc = shift;
  my $lang = shift;
	my $index_inst = shift;

  my @locations = $root->getElementsByTagName( lib::OUT_BASE::ELEMENT_LOCATION );
  foreach my $location (@locations) {
    my $lon = get_element_data( $location, lib::OUT_BASE::ELEMENT_LONGITUDE );
    my $lat = get_element_data( $location, lib::OUT_BASE::ELEMENT_LATITUDE );
    my $street = get_element_data( $location, lib::OUT_BASE::ELEMENT_STREET );
    my $city = get_element_data( $location, lib::OUT_BASE::ELEMENT_CITY );

    my $orgname = '';
    #$orgname = $r_realm->{ lib::CONF_SHARED::ORGNAME .'_'. $lang } if defined $r_realm->{ lib::CONF_SHARED::ORGNAME .'_'. $lang };
    $orgname = (get_desc( $r_realm, $lang, $type_desc, $index_inst )); # .', '. $street.', '.$city;

    my $desc = $street.", ".$city ."\n";
    #print Dumper( $orgname );

    my $ssid = get_element_data( $location, lib::OUT_BASE::ELEMENT_SSID );
    my $enc_level = get_element_data( $location, lib::OUT_BASE::ELEMENT_ENC_LEVEL );
    my $port_restrict = get_element_data( $location, lib::OUT_BASE::ELEMENT_PORT_RESTRICT );
    my $ipv6 = get_element_data( $location, lib::OUT_BASE::ELEMENT_IPv6 );
    my $wired = get_element_data( $location, lib::OUT_BASE::ELEMENT_WIRED );
    my $proxy = get_element_data( $location, lib::OUT_BASE::ELEMENT_PROXY );
    my $info_url = get_element_data( $location, lib::OUT_BASE::ELEMENT_INFO_URL );
    my $nat = get_element_data( $location, lib::OUT_BASE::ELEMENT_NAT );

    $desc .= msg_print( lib::OUT_BASE::ELEMENT_SSID,  $lang ) . $ssid ."\n";
    $desc .= msg_print( lib::OUT_BASE::ELEMENT_ENC_LEVEL, $lang ) . $enc_level ."\n";

    if ((defined $wired) && (($wired eq lib::OUT_BASE::ATTR_TRUE) || ($wired eq lib::OUT_BASE::ATTR_1 ))) {
      $desc .= msg_print( lib::OUT_BASE::MSG_WIRED, $lang );
    } else {
      $desc .= msg_print( lib::OUT_BASE::MSG_NO_WIRED, $lang );
    }

    if (($ipv6 eq lib::OUT_BASE::ATTR_TRUE) || ($ipv6 eq lib::OUT_BASE::ATTR_1)) {
      $desc .= msg_print( lib::OUT_BASE::MSG_IPV6, $lang );
    } else {
      $desc .= msg_print( lib::OUT_BASE::MSG_IPV4, $lang );
    }

    if (($port_restrict eq lib::OUT_BASE::ATTR_TRUE) || ($port_restrict eq lib::OUT_BASE::ATTR_1)) {
      $desc .= msg_print( lib::OUT_BASE::MSG_PORT_RESTRICT, $lang );
    } else {
      $desc .= msg_print( lib::OUT_BASE::MSG_NO_PORT_RESTRICT, $lang );
    }
    
    if (($nat eq lib::OUT_BASE::ATTR_TRUE) || ($nat eq lib::OUT_BASE::ATTR_1)) {
      $desc .= msg_print( lib::OUT_BASE::MSG_NAT, $lang );
    } else {
      $desc .= msg_print( lib::OUT_BASE::MSG_NO_NAT, $lang );
    }

    if (($proxy eq lib::OUT_BASE::ATTR_TRUE) || ($proxy eq lib::OUT_BASE::ATTR_1)) {
      $desc .= msg_print( lib::OUT_BASE::MSG_TRANS_PROXY, $lang );
    } else {
      $desc .= msg_print( lib::OUT_BASE::MSG_NO_TRANS_PROXY, $lang );
    }
    
    my $link = '';
    if ((defined $info_url) && ($info_url ne "http://www.doplnit-url.cz/en/procizi/index.html" )) { 
      $link = $info_url;
      #} else {
      #$info_url = '';
    }
    

    next if ($lat eq 0);
    next if ($lon eq 0);
    my %point = ( ATTR_LAT => $lat, ATTR_LON => $lon, ELEMENT_NAME => $orgname, ELEMENT_DESC => $desc, ELEMENT_LINK => $link );

    push @$r_wpts, \%point;
  }

}

# lookfor every waypoint in xmls
sub add_all_waypoints {
  my $r_realms = shift;
  my $r_xml = shift;
	my $type_desc = shift;
  my $lang = shift;

  my @wpts;

  foreach my $index (keys %$r_realms ) {
    add_org_waypoints( $r_realms->{$index}, \@wpts, $r_xml->{ $index }, $type_desc, $lang, $index ) if defined $r_xml->{ $index };
  }

  return @wpts;

}

# external api function
sub out_gpx {
  my $r_realms = shift;  # config data
  my $tree = shift;  # tree depency
  my $out_file = shift;  # output file
  my $cachedir = shift;  # cache dir
  my $ext_cache = shift;  # cache file extension
  my $lang = shift;  # selected output language
  my $type_desc = shift;  # selected output description ( orgname || acronym )
  my $encoding = shift;  # encoding of output xml
  my $tidy_xml = shift;

  my %xml = out_preread_xml( $r_realms, $cachedir, $ext_cache );

  # we need create array of waypoints, whiches we add to gpx file
  my @wpts = add_all_waypoints( $r_realms, \%xml, $type_desc, $lang );

	my @sorted_wpts = sort { $a->{ELEMENT_NAME} cmp $b->{ELEMENT_NAME} } @wpts;

	my $doc = XML::LibXML::Document->new('1.0', $encoding);
	my $root = $doc->createElement( ELEMENT_GPX );
	$doc->setDocumentElement($root);

	$root->setAttribute( ATTR_XMLNS, ATTR_XMLNS_VALUE );
	$root->setAttribute( ATTR_XSI, ATTR_XSI_VALUE );
	$root->setAttribute( ATTR_SCHEMA, ATTR_SCHEMA_VALUE );
	$root->setAttribute( ATTR_VERSION, ATTR_VERSION_VALUE );
	$root->setAttribute( ATTR_CREATOR, ATTR_CREATOR_VALUE );

	foreach my $wpt (@sorted_wpts) {
		my $xml_wpt = $doc->createElement( ELEMENT_WPT );

		next if (dms2decimal( $wpt->{ ATTR_LAT }) eq 0);
		next if (dms2decimal( $wpt->{ ATTR_LON }) eq 0);
		$xml_wpt->setAttribute( ATTR_LAT, dms2decimal( $wpt->{ ATTR_LAT }) );
		$xml_wpt->setAttribute( ATTR_LON, dms2decimal( $wpt->{ ATTR_LON }) );

		my $xml_name = $doc->createElement( ELEMENT_NAME );
		$xml_wpt->appendChild( $xml_name );
		my $name_data = XML::LibXML::Text->new( $wpt->{ ELEMENT_NAME } );
		$xml_name->appendChild( $name_data );
		
		my $xml_desc = $doc->createElement( ELEMENT_DESC );
		$xml_wpt->appendChild( $xml_desc );
		my $desc_data = XML::LibXML::Text->new( $wpt->{ELEMENT_DESC} );
		$xml_desc->appendChild( $desc_data );

		if( $wpt->{ELEMENT_LINK} ne '' ) {
  		my $xml_link = $doc->createElement( ELEMENT_LINK );
			$xml_link->setAttribute( ATTR_HREF, $wpt->{ ELEMENT_LINK } );
	  	$xml_wpt->appendChild( $xml_link );
		  my $link_data = XML::LibXML::Text->new( msg_print( lib::OUT_BASE::MSG_INFO_URL, $lang ) );
		  $xml_link->appendChild( $link_data );
		}

		$root->appendChild( $xml_wpt );

	}

  my $handle = new IO::File;
  open($handle, '>:utf8', $out_file) or
    log_die("out_gpx: Can't open file: $out_file: $!");

  my $xml_string = $doc->toString;

  if ($tidy_xml) {
    my $tidy = XML::Tidy->new(xml => $doc->toString);
    if ($tidy) {
      eval { $tidy->tidy };
      if ($@) {
      	# Tidy dump all invalid XML to err, it's too long for
	      # syslog. So I'm trying to make it shorter.
	      my $err = substr($@, 0, 256);
	      log_it(LOG_ERR, "Failed to create XML::Tidy object, writing untided XML: $err");
      } else {
	      $xml_string = $tidy->toString;
      };
    } else {
      log_it(LOG_ERR, "Failed to create XML::Tidy object, writing untided XML");
    };
  };

  print $handle $xml_string;

  close($handle);

}


1;
