# output base package
# shared code for all output modules
# vim: set encoding=utf-8

package lib::OUT_BASE;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&out_preread_xml &dms2decimal &get_desc &sort_conf_data &msg_print &get_element_data);

use Sys::Syslog qw(:standard :macros);
use lib::LOG;
use Data::Dumper;
use utf8;
use Unicode::String qw(utf8 latin1 utf16);
use Encode qw(encode decode);
use locale;
use POSIX qw(strftime locale_h);
use lib::CONF_SHARED;
use JSON;

# !!! default language, get_desc used it, if $lan variable isn't defined
use constant LANG_DEF => 'en';

use constant ELEMENT_LOCATION => 'location';
use constant ELEMENT_LONGITUDE => 'longitude';
use constant ELEMENT_LATITUDE => 'latitude';
use constant ELEMENT_ADDRESS => 'address';
use constant ELEMENT_STREET => 'street';
use constant ELEMENT_CITY => 'city';
use constant ELEMENT_LOCNAME => 'loc_name';
use constant ELEMENT_INSTITUTION => 'institution';
use constant ELEMENT_SSID => 'SSID';
use constant ELEMENT_ENC_LEVEL => 'enc_level';
use constant ELEMENT_PORT_RESTRICT => 'port_restrict';
use constant ELEMENT_PROXY => 'transp_proxy';
use constant ELEMENT_IPv6 => 'IPv6';
use constant ELEMENT_INFO_URL => 'info_URL';
use constant ELEMENT_WIRED => 'wired';
use constant ELEMENT_NAT => 'NAT';

use constant MSG_SSID => 'SSID';
use constant MSG_ENC_LEVEL => 'enc_level';
use constant MSG_IPV4 => 'IPv4';
use constant MSG_IPV6 => 'IPv6';
use constant MSG_PORT_RESTRICT => 'port_restrict';
use constant MSG_NO_PORT_RESTRICT => 'no_port_restrict';
use constant MSG_TRANS_PROXY => 'trans_proxy';
use constant MSG_NO_TRANS_PROXY => 'no_trans_proxy';
use constant MSG_WIRED => 'wired';
use constant MSG_NO_WIRED => 'no_wired';
use constant MSG_NAT => 'NAT';
use constant MSG_NO_NAT => 'no_NAT';
use constant MSG_INFO_URL => 'info_url';

use constant ATTR_TRUE => 'true';
use constant ATTR_1 => '1';
use constant ATTR_FALSE => 'false';
use constant ATTR_0 => '0';

# national messages
use constant MSG_YES => 'yes';
use constant MSG_NO => 'no';

my %msg = (
	lib::OUT_BASE::MSG_SSID => { en => 'essid: ',
							cs => 'essid: ' },
  lib::OUT_BASE::MSG_ENC_LEVEL =>  { en => 'encryption: ',
										cs => 'šifrování: ' },
	lib::OUT_BASE::MSG_IPV6 => { en => 'IPv4+6; ',
							cs => 'IPv4+6; ' },
	lib::OUT_BASE::MSG_IPV4 => { en => 'IPv4; ',
						  cs => 'IPv4; ' },
  lib::OUT_BASE::MSG_PORT_RESTRICT => { en => 'FW + ',
											cs => 'FW + ' },
	lib::OUT_BASE::MSG_NO_PORT_RESTRICT => { en => 'w/o FW + ',
													cs => 'žádný FW + '},
	lib::OUT_BASE::MSG_TRANS_PROXY => { en => 'proxy',
											cs => 'proxy' },
	lib::OUT_BASE::MSG_NO_TRANS_PROXY => { en => 'w/o proxy',
												cs => 'žádná proxy' },
  lib::OUT_BASE::MSG_WIRED => { en => 'connectivity: WiFi+wired; ',
							cs => 'konektivita: WiFi+kabel; ' },
	lib::OUT_BASE::MSG_NO_WIRED => { en => 'connectivity: WiFi; ',
									cs => 'konektivita: WiFi; '},
	lib::OUT_BASE::MSG_NAT => { en => 'NAT + ',
						 cs => 'NAT + ' },
	lib::OUT_BASE::MSG_NO_NAT => { en => 'public IP + ',
								cs => 'veřejné IP +  '},
	lib::OUT_BASE::MSG_YES => { en => 'yes',
						cs => 'ano' },
	lib::OUT_BASE::MSG_NO => { en => 'no',
						cs => 'ne' },
	lib::OUT_BASE::MSG_INFO_URL => { en => 'More informations ...',
									cs => 'Informace pro návštěvníky' },

									);

# print national message
sub msg_print {
	my $index = shift;
	my $lang = shift;

	my $something =  $msg{ $index }{ $lang };
	#print Dumper $something;
	return $something;
}

# get element data
sub get_element_data {
  my $node = shift;  # where
  my $element = shift;  # what

  foreach my $res (@{$node->getElementsByTagName($element)}) {
    my $first_child = $res->getFirstChild;

    next unless $first_child;
    return $first_child->getData;
  };

  return;
};

# pre-read xml from cache (!!! cache is created by get_institution.pl )
sub out_preread_xml {
    my $r_realms = shift;
    my $cachedir = shift;
    my $ext_cache = shift;

    my %xml;

    foreach my $realm (keys %$r_realms) {
	my $f_cache = $cachedir."/".$realm.$ext_cache;

	if( ! -f $f_cache ) {
	    log_it( LOG_INFO, "out_dokuwiki(): Cache file doesn't exists (". $f_cache ."), maybe virtual organization." );
	    next;
	}

	if (open(F, "$f_cache")) {
	    my $json_string = join('', <F>);
	    my $json = decode_json($json_string);
	    close(F);
	    $xml{ $realm } = $json;
	} else {
	    log_it( LOG_INFO, "out_dokuwiki(): Cache file (". $f_cache ."), failed to read: ".$! );
	    next;
	};
    };

    return %xml;
}

# convert coordinations to format used in kml
sub dms2decimal {
  my $x = shift;

  #print Dumper( $x);
  (my $degree, my $mins, my $sec, my $quadrate) = $x =~ /^\D*(\d+)\D+([0-9\.]+)\D+([0-9\.+]+)\D(\w)/; #\W([E-W])/; # 14\x<b0>23'26.613"E
  #print "deg: $degree\n";
  #print "min: $mins\n";
  #print "sec: $sec\n";
  #print "$quadrate\n";

  if( defined $degree && defined $mins && defined $sec && defined $quadrate ) {
#    $sec = $sec + ( $secdot / 1000 );
    my $res = ($degree + (($mins)/60) + (($sec)/3600));

    $res = $res * -1 if ( $quadrate =~ /^S/ || $quadrate =~ /^W/ );
    #print "res: $res\n";

    return $res;
  }
  #print "\n\n";

  log_it( LOG_WARNING, "dms2decimal(): Syntax error in coordinates: $x" );
  return 0;
}

# split_desc
sub split_desc {
	my $desc = shift;

	return split(/,/, $desc);
}

# get desription of an organization
sub get_desc {
 my $r_realm = shift;
 my $lang = shift;
 my $type_desc = shift;
 my $institution = shift;

 my @tested_indexes;
 foreach my $index (split_desc($type_desc)) {
   my $data_index = $index.'_'.$lang;
	 #print Dumper $data_index;
   push @tested_indexes, $data_index;
   if (defined($r_realm->{$data_index})) {
		 #print Dumper $r_realm->{$data_index};
     return ($r_realm->{$data_index});
   };
 };

 # same for default language
 #$lang = LANG_DEF;
 #foreach my $index (split_desc($type_desc)) {
 #  my $data_index = $index.'_'.$lang;
#	 #print Dumper $data_index;
#   push @tested_indexes, $data_index;
#   if (defined($r_realm->{$data_index})) {
#		 #print Dumper $r_realm->{$data_index};
#     return $r_realm->{$data_index};
#   };
# };

 foreach my $key (%{$r_realm}) {
     next unless (exists($r_realm->{$key}));
     my $key_string = Dumper($r_realm->{$key});
     log_it(LOG_DEBUG,
	    "get_desc: there is not defined value ".join(', ', @tested_indexes).", using $key = ".$key_string);
     return '';
 };

 return '';
}

# sort
sub sort_conf_data {
    my $a_realm = shift;
    my $b_realm = shift;
    my $sortby = shift;
    my $lang = shift;

    my $i1 = 0;
    my $i2 = 0;
    my $a;
    my $b;

    foreach my $index (split_desc($sortby)) {
	my $data_index = $index.'_'.$lang;

	if( defined $a_realm->{ $data_index } ) {
	    if ($i1==0) {
		$i1 = 1;
		$a = $a_realm->{ $data_index };
	    }
	} elsif (($i1==0) && ( defined $a_realm->{ $index.'_'.lib::OUT_BASE::LANG_DEF } )) {
	    $i1 = 1;
	    $a = $a_realm->{ $index.'_'.lib::OUT_BASE::LANG_DEF };
	}


	if( defined $b_realm->{ $data_index } ) {
	    if ($i2==0) {
		$i2 = 1;
		$b = $b_realm->{ $data_index };
	    }
	} elsif (($i2==0) && ( defined $b_realm->{ $index.'_'.lib::OUT_BASE::LANG_DEF } )) {
	    $i2=1;
	    $b = $b_realm->{ $index.'_'.lib::OUT_BASE::LANG_DEF };
	}

	return ( $a cmp $b ) if (($i1==1)&&($i2==1));
    }
}


# end of module
1;
