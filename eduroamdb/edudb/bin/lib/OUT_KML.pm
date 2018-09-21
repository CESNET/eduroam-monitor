#
#generate kml (google earth) document

package lib::OUT_KML;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&out_kml);

use Tree;
use Sys::Syslog qw(:standard :macros);
use lib::LOG;
use lib::CONF_SHARED;
use lib::OUT_BASE;
use Data::Dumper;
use locale;
use XML::Tidy;
use Encode qw(encode decode);

# used elemens in kml output
use constant ELEMENT_KML => 'kml';
use constant ELEMENT_DOCUMENT => 'Document';
use constant ELEMENT_NAME => 'name';
use constant ELEMENT_PLACEMARK => 'Placemark';
use constant ELEMENT_POINT => 'Point';
use constant ELEMENT_COORDINATES => 'coordinates';
use constant ELEMENT_FOLDER => 'Folder';
use constant ELEMENT_ADDRESS => 'address';
use constant ELEMENT_DESCRIPTION => 'description';
use constant ELEMENT_OPEN => 'open';

# used attrs
use constant ATTR_XMLNS_VALUE => 'http://www.opengis.net/kml/2.2';
use constant ATTR_XMLNS => 'xmlns';

# our eduroam
use constant DOC_NAME => 'eduroam.cz';


# lookfor all location element in particular xml
sub add_org_waypoints {
  my $r_realm = shift;
  my $r_wpts = shift;
  my $root = shift;
  my $lang = shift;

  my @locations = $root->getElementsByTagName( lib::OUT_BASE::ELEMENT_LOCATION );
  foreach my $location (@locations) {
    my $lon = get_element_data( $location, lib::OUT_BASE::ELEMENT_LONGITUDE );
    my $lat = get_element_data( $location, lib::OUT_BASE::ELEMENT_LATITUDE );

    my $street = get_element_data( $location, lib::OUT_BASE::ELEMENT_STREET );
    my $city = get_element_data( $location, lib::OUT_BASE::ELEMENT_CITY );

    my $orgname = '';
    $orgname = $r_realm->{ lib::CONF_SHARED::ORGNAME .'_'. $lang } if defined $r_realm->{ lib::CONF_SHARED::ORGNAME .'_'. $lang };
    my $loc_name = get_element_data($location, lib::OUT_BASE::ELEMENT_LOCNAME);
    $orgname .= " - $loc_name" if defined($loc_name);
    my $desc = "<div><span>".$street.", ".$city ." </span>";

    my $ssid = get_element_data( $location, lib::OUT_BASE::ELEMENT_SSID );
    my $enc_level = get_element_data( $location, lib::OUT_BASE::ELEMENT_ENC_LEVEL );
    my $port_restrict = get_element_data( $location, lib::OUT_BASE::ELEMENT_PORT_RESTRICT );
    my $ipv6 = get_element_data( $location, lib::OUT_BASE::ELEMENT_IPv6 );
    my $wired = get_element_data( $location, lib::OUT_BASE::ELEMENT_WIRED );
    my $proxy = get_element_data( $location, lib::OUT_BASE::ELEMENT_PROXY );
    my $info_url = get_element_data( $location, lib::OUT_BASE::ELEMENT_INFO_URL );
    my $nat = get_element_data( $location, lib::OUT_BASE::ELEMENT_NAT );

    $desc .= '<div><span>'. msg_print( lib::OUT_BASE::ELEMENT_SSID,  $lang ) . $ssid .' </span></div>';

    $desc .= '<div><span>'. msg_print( lib::OUT_BASE::ELEMENT_ENC_LEVEL, $lang ) . $enc_level .' </span></div>';

    $desc .= '<div>';

    if ((defined $wired) && (($wired eq lib::OUT_BASE::ATTR_TRUE) || ($wired eq lib::OUT_BASE::ATTR_1 ))) {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_WIRED, $lang ).'</span>' ;
    } else {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_NO_WIRED, $lang ).'</span>' ;
    }

    if (($ipv6 eq lib::OUT_BASE::ATTR_TRUE) || ($ipv6 eq lib::OUT_BASE::ATTR_0)) {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_IPV6, $lang ) .'</span>' ;
    } else {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_IPV4, $lang ) .'</span>' ;
    }

    if (($port_restrict eq lib::OUT_BASE::ATTR_TRUE) || ($port_restrict eq lib::OUT_BASE::ATTR_1)) {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_PORT_RESTRICT, $lang ) .'</span>';
    } else {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_NO_PORT_RESTRICT, $lang ) .'</span>';
    }

    if (($nat eq lib::OUT_BASE::ATTR_TRUE) || ($nat eq lib::OUT_BASE::ATTR_1)) {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_NAT, $lang )  .'</span>' ;
    } else {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_NO_NAT, $lang )  .'</span>' ;
    }

    if (($proxy eq lib::OUT_BASE::ATTR_TRUE) || ($proxy eq lib::OUT_BASE::ATTR_1)) {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_TRANS_PROXY, $lang ).'</span>';
    } else {
      $desc .= '<span>'. msg_print( lib::OUT_BASE::MSG_NO_TRANS_PROXY, $lang ).'</span>';
    }
		
    $desc .= '</div><div class=separator></div>';
    if ((defined $info_url) && ($info_url ne "http://www.doplnit-url.cz/en/procizi/index.html" )) { 
      $desc .= '<div><span><a href='. $info_url .'>'. msg_print( lib::OUT_BASE::MSG_INFO_URL, $lang ).'</a></span></div>'  ;
    } else {
      $info_url = '';
    }

    $desc .= '</div>';

    my %point = ( ATTR_LAT => $lat, ATTR_LON => $lon, ELEMENT_NAME => $orgname, ELEMENT_DESCRIPTION => $desc, ELEMENT_INFO_URL => $info_url );

    push @$r_wpts, \%point;
  }
}

# create kml folder
sub kml_create_folder {
  my $doc = shift;
  my $elem_doc = shift;
  my $data = shift;

  # create folder
  my $elem_folder = $doc->createElement( ELEMENT_FOLDER );
  $elem_doc->appendChild( $elem_folder );

  # name of folder
  my $elem_name = $doc->createElement( ELEMENT_NAME );
  $elem_folder->appendChild( $elem_name );
  my $name_data = XML::LibXML::Text->new( $data );
  $elem_name->appendChild( $name_data );

	my $elem_open = $doc->createElement( ELEMENT_OPEN );
	$elem_folder->appendChild( $elem_open );
	my $open_data = XML::LibXML::Text->new( "0" );
	$elem_open->appendChild( $open_data );


  return $elem_folder;
}



# recursive function
sub process_data {
  my $r_realms = shift;
  my $tree = shift;
  my $r_xml = shift;
  my $r_doc = shift;
  my $elem_doc = shift;
  my $type_desc = shift;
  my $lang = shift;

  my %xml = %$r_xml;
  
  # select nodes from this level
  my @nodes = $tree->children();

	# we must sort it first
	#my $sortby = $type_desc ."_". $lang;
	my @sorted = sort { sort_conf_data( $r_realms->{ $a->value }, $r_realms->{ $b->value }, $type_desc, $lang ) } @nodes;


  foreach my $node (@sorted) {
    my $deb_realm = $r_realms->{ $node->value };

		#print Dumper( $node);

      # create folder for placemarks
      my $desc = get_desc( $deb_realm, $lang, $type_desc, $node->value );
      my $elem_folder = kml_create_folder( $r_doc, $elem_doc, $desc );
			#print "udelej folder ". $desc ."\n"; 

			process_data( $r_realms, $node, $r_xml, $r_doc, $elem_folder, $type_desc, $lang ) if (! $node->is_leaf );

      # create placemarks
      if( defined $xml{ $node->value } ) {
				#print "xml{node->value} ". $node->value ."\n";
        my @wpts;
        add_org_waypoints( $r_realms->{$node->value}, \@wpts, $xml{ $node->value }, $lang );

        foreach my $wpt (@wpts) {
	  #print Dumper( $wpt );
          #print Dumper $r_doc;
          my $elem_placemark = $r_doc->createElement( ELEMENT_PLACEMARK );

	  # icon of placemark
	  my $styleUrl = $r_doc->createElement('styleUrl');
	  $styleUrl->appendTextNode('#eduroamIcon');
	  $elem_placemark->appendChild($styleUrl);

	  # name of placemark
          my $elem_name = $r_doc->createElement( ELEMENT_NAME );
          $elem_placemark->appendChild( $elem_name );
          my $name_data = XML::LibXML::Text->new( $desc );
	  # SEMIK: Rekl bych ze by se tady mel pouzivat nazev lokality
	  $name_data->setData($wpt->{ELEMENT_NAME});
          $elem_name->appendChild( $name_data );

          my $elem_description = $r_doc->createElement( ELEMENT_DESCRIPTION );
	  $elem_placemark->appendChild( $elem_description );
	  #my $description_data = XML::LibXML::Text->new( $wpt->{ ELEMENT_DESCRIPTION } );
	  my $description_data = $r_doc->createTextNode( $wpt->{ ELEMENT_DESCRIPTION } );
	  $elem_description->appendChild( $description_data );

	  my $elem_point = $r_doc->createElement( ELEMENT_POINT );
          $elem_placemark->appendChild( $elem_point );

	  my $elem_coord = $r_doc->createElement( ELEMENT_COORDINATES );
	  $elem_point->appendChild( $elem_coord );
	  next if (dms2decimal( $wpt->{ ATTR_LON } ) eq 0);
	  next if (dms2decimal( $wpt->{ ATTR_LAT } ) eq 0);
	  my $coord_data = XML::LibXML::Text->new( dms2decimal( $wpt->{ ATTR_LON } ) .','. dms2decimal( $wpt->{ ATTR_LAT } .',0' ));
	  $elem_coord->appendChild( $coord_data );


          $elem_folder->appendChild( $elem_placemark );
					
        }
      }
  }
}

# external api function
sub out_kml {
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

	my $doc = XML::LibXML::Document->new('1.0', $encoding);
	my $root = $doc->createElementNS( ATTR_XMLNS_VALUE, ELEMENT_KML );
	$doc->setDocumentElement($root);

	#$root->setAttribute( ATTR_XMLNS, ATTR_XMLNS_VALUE );

  my $elem_doc = $doc->createElement( ELEMENT_DOCUMENT );
  $root->appendChild( $elem_doc );

	my $doc_name = $doc->createElement( ELEMENT_NAME );
	$elem_doc->appendChild( $doc_name );

	my $edu_name = XML::LibXML::Text->new( DOC_NAME );
	$doc_name->appendChild( $edu_name );

  # icon of placemark
  my $icon_href = $doc->createElement('href');
  $icon_href->appendTextNode('https://monitor.eduroam.cz/images/map_icon8.png');
  my $icon = $doc->createElement('Icon');
  $icon->appendChild($icon_href);
  my $scale = $doc->createElement('scale');
  $scale->appendTextNode('0');
  my $icon_style = $doc->createElement('IconStyle');
  $icon_style->appendChild($icon);
  $icon_style->appendChild($scale);
  my $style = $doc->createElement('Style');
  $style->setAttribute('id', 'eduroamIcon');
  $style->appendChild($icon_style);
  $elem_doc->appendChild($style);


  # go through tree and create xml marks
  process_data( $r_realms, $tree, \%xml, $doc, $elem_doc, $type_desc, $lang );

  # write result to output file
  my $handle = new IO::File;
  open($handle, '>:utf8', $out_file) or
    log_die( "out_kml: Can't open file $out_file: $!");

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

  close( $handle );
};








1;
