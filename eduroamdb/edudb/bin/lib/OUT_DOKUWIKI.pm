# output dokuwiki package

package lib::OUT_DOKUWIKI;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&out_dokuwiki);

use Tree;
use lib::TREE_OPS;
use Sys::Syslog qw(:standard :macros);
use lib::LOG;
use lib::CONF_SHARED;
use lib::OUT_BASE;
use locale;
use Data::Dumper;
use utf8;
use Unicode::String qw(utf8);
#use Cz:Sort;
#use Encode qw(encode decode);


# empty string 
use constant EMPTY_LOCNAME => 'ZZZZZZZZZZZZ_empty_locname';
use constant COUNTER_SON => 'sssson';  # index to hash

# get info url
sub get_info_url {
  my $r_xml = shift;
	my $index = shift;
	my $lang = shift;
	
  my $info_url = "";
	my $info_url_other_lang = "";
	my $first_match = 0;
	if (defined $r_xml->{$index}) {
    my $xml = $r_xml->{ $index };
		my @urls = $xml->getElementsByTagName( lib::CONF_SHARED::INFO_URL );
		foreach my $t_url (@urls) {
      #print Dumper( $t_url );
			if( $t_url->getAttribute( 'lang' ) eq $lang ) {
				if (defined $t_url->getFirstChild ) {
  				$info_url = $t_url->getFirstChild->getData if defined $t_url->getFirstChild;
					#print Dumper $info_url;
		  		$first_match = 1;
  				# first match is ok
  				last;
				}
			} else {
				$info_url_other_lang = $t_url->getFirstChild->getData if defined $t_url->getFirstChild;
				#log_it( LOG_WARNING, "info_url is not defined !" );
				#return "";

			}
		}
	}

	# if not info_url in certain language available => use other available
	$info_url = $info_url_other_lang if ! $first_match;

	return $info_url;

}

sub get_value {
  my $a = shift;

  if (defined($a)) {
    $a = $a->[0];
    if (defined($a)) {
      $a = $a->getFirstChild;
      if (defined($a)) {
	my $v = $a->getData || '';
	$v =~ s/^\s*//;
	$v =~ s/\s*$//;

	return $v;
      };
    };
  };

  return;
};

sub print_address {
  my $city = shift;
  my $street = shift;

  my @e = (get_value($street), get_value($city));

  return join(', ', @e);
};

sub print_address2 {
  my $city = shift;
  my $street = shift;

  my $address;

  eval {
    $address = sprintf("%s, %s",
		       $city->[0]->getFirstChild->getData,
      		       $street->[0]->getFirstChild->getData);
  };

  return if ($@);
  return $address;
};

# get institution address
sub get_institution_address {
  my $r_xml = shift;
  my $index = shift;

  if( defined $r_xml->{ $index } ) {
    my $xml = $r_xml->{ $index };

    my $address = "";

    my @insts = $xml->getElementsByTagName( lib::OUT_BASE::ELEMENT_INSTITUTION );
    foreach my $inst (@insts) {
      my @addresses = $inst->getChildrenByTagName( lib::OUT_BASE::ELEMENT_ADDRESS );
      foreach my $addr (@addresses) {
        my @street = $addr->getElementsByTagName( lib::OUT_BASE::ELEMENT_STREET );
        my @city   = $addr->getElementsByTagName( lib::OUT_BASE::ELEMENT_CITY );

        if( defined $street[0] && defined $city[0] ) {
	    $address = ($street[0]->getFirstChild->getData .", ". $city[0]->getFirstChild->getData);
	    return $address;
        }
      }
    }
  }
	return "";
}

# get location address
sub get_location_address {
  my $r_xml = shift;
  my $index = shift;

  if( defined $r_xml->{ $index } ) {
    my $xml = $r_xml->{ $index };

    my $address = "";

    #my @locs = $xml->getElementsByTagName( lib::OUT_BASE::ELEMENT_LOCATION );
    #foreach my $loc (@locs) {
    my @addresses = $xml->getChildrenByTagName( lib::OUT_BASE::ELEMENT_ADDRESS );
    foreach my $addr (@addresses) {
      my @street = $addr->getElementsByTagName( lib::OUT_BASE::ELEMENT_STREET );
      my @city   = $addr->getElementsByTagName( lib::OUT_BASE::ELEMENT_CITY );

      $address = print_address(\@city, \@street);
				
      #print Dumper @street;

#      if( defined $street[0]->getFirstChild && defined $city[0]->getFirstChild ) {
	#if (defined($sf) and defined($cf)) {
#	$address = ($street[0]->getFirstChild->getData .", ". $city[0]->getFirstChild->getData);
	#my $temp_street = $street[0]->getFirstChild->getData;
	#my $temp_city = $city[0]->getFirstChild->getData;
	#$address = $temp_street if defined $temp_street;
	#$address .= ", " if defined $temp_street && defined $temp_city;
	#$address .= $temp_city if defined $temp_city;
      
      #SEMIK return utf8($address);
      return $address;

	#};
#      }
    }
    #}
  }
  #return "unknow";
}

# recursive call of get_locations 
sub get_loc_recursive {
  my $r_realms = shift;
	my $r_xml = shift;
	my $lang = shift;
	my $print_empty = shift;
  my $tree = shift;

	my @nodes = $tree->children();
	foreach my $node (@nodes) {
		get_locations( $r_realms, $r_xml, $node->value, $node,  $lang, $print_empty );

		get_loc_recursive( $r_realms, $r_xml, $lang, $print_empty, $node );
	}
}

# get locations form xml
sub get_locations {
	my $r_realms = shift;
	my $r_xml = shift;
	my $index = shift;
	my $node = shift;
	my $lang = shift;
	my $print_empty = shift;

	my @locs;

	my $loc_suffix = 1;

	if( defined $r_xml->{$index} ) {
		my $xml = $r_xml->{$index};
		
		my @locations = $xml->getElementsByTagName( lib::OUT_BASE::ELEMENT_LOCATION );
		foreach my $loc (@locations) {
			# look for loc_name
			my @loc_names = $loc->getElementsByTagName( lib::OUT_BASE::ELEMENT_LOCNAME );

			my %realm_hash;
			my $new_one;

      # look for loc_name in different language
			foreach my $loc_name (@loc_names) {
				next unless defined $loc_name;
				next unless defined $loc_name->getFirstChild;
				$new_one = $loc_name->getFirstChild->getData;

				next if ! defined $new_one;
				

				my $aloc_name = $loc_name->getAttribute( 'lang' );

				#print "aloc_name\n";
				#print Dumper $aloc_name;
				#print Dumper $new_one;


			  $realm_hash{lib::CONF_SHARED::ORGNAME."_".$aloc_name} = ( $new_one);
				$realm_hash{lib::CONF_SHARED::ORGUNITNAME."_".$aloc_name} = ( $new_one);
				$realm_hash{lib::CONF_SHARED::ACRONYM."_".$aloc_name} = ( $new_one);
				$realm_hash{lib::CONF_SHARED::ACROUNIT."_".$aloc_name} = ( $new_one);
		  }
			
			# if print empty => check if loc_name is defined 
			if ($print_empty) {
					if( ! defined $realm_hash{lib::CONF_SHARED::ORGNAME."_".$lang} ) {
						$new_one = EMPTY_LOCNAME;
						$realm_hash{lib::CONF_SHARED::ORGNAME."_".$lang} = ( $new_one);
		        $realm_hash{lib::CONF_SHARED::ORGUNITNAME."_".$lang} = ( $new_one);
		        $realm_hash{lib::CONF_SHARED::ACRONYM."_".$lang} = ( $new_one);
		        $realm_hash{lib::CONF_SHARED::ACROUNIT."_".$lang} = ( $new_one);

					}
			}

			my $new_index = $index."_".$loc_suffix;
			#print Dumper $new_index;

			$r_realms->{$new_index} = \%realm_hash;

			#print Dumper $r_realms->{$new_one}{lib::CONF_SHARED::ORGNAME." ".$lang};
					
			# inject node for hierarchy
			my %known_realms;  # it is needed only for function call
			if (defined($new_one)) {
			  $known_realms{$new_one} = 1;
			  insert_child( $node, $new_index, \$known_realms{$new_one} );
			};

			# inject xml data
			$r_xml->{$new_index} = $loc;

			# store counts of sons
			$r_realms->{$index}{COUNTER_SON} = $loc_suffix;

			$loc_suffix++;
				
	  }
  }
}

# print row
# if not description defined => don't print the row ( print due to option PRINT_EMPTY_DESCRIPTION
# if not url defined => don't create link (print only description)
sub print_row {
  my $r_realms = shift;  
	my $r_xml = shift;
	my $node = shift;
	my $r_handle = shift;
	my $prefix = shift;
	my $lang = shift;
	my $type_desc = shift;
	my $print_empty = shift;

	my $index = $node->value;

	# prepare needed data
	# get info url
	my $info_url = get_info_url( $r_xml, $index, $lang );

	# try use info url of parent
	if( $info_url eq "" ) {
		my $parent = $node->parent();
		$info_url = get_info_url( $r_xml, $parent->value, $lang );
	}

	my $description = get_desc( $r_realms->{ $index }, $lang, $type_desc, $index );
	#print Dumper $description;


	# print something only if description is defined
	if(( ! $description eq "" ) || ($print_empty)){
  	# prefix (numbers of spaces)
		my $row = $prefix ."* ";
	
		my $addr = get_institution_address($r_xml, $index);
		$addr = get_location_address($r_xml, $index) if( $addr eq "" );

		if( $description eq "" ) {
		  # try def language
		  $description = get_desc( $r_realms->{ $index }, lib::OUT_BASE::LANG_DEF, $type_desc, $index );
	  	}

		my $empty_locname = EMPTY_LOCNAME;
		if( $description =~ /$empty_locname/ ) {
			$description = "";
		}

		# don't print address, if it is container
		$addr = "" if(( defined $r_realms->{$index}{COUNTER_SON} ) && ( $r_realms->{$index}{COUNTER_SON} > 1 ));

		my $fancy_desc = "";
		if( $info_url eq "" ) {
			if( $addr eq "" ) {
				$fancy_desc = $description if $description ne "" ;
			} else {
			  $fancy_desc = $description .", " if $description ne "" ;
			}
			$row .= $fancy_desc. $addr;
		} else {
			if( $addr eq "" ) {
				$fancy_desc = $description if $description ne "" ;
			} else {
			  $fancy_desc = $description .", " if $description ne "";
			}
			$row .= "[[ ". $info_url ."|". $fancy_desc . $addr ."]]";
		}
		
		# SEMIK: Puvodne se volalo jen na casti a to zacalo zpusobovat trable 22.6.2015
		print { $$r_handle } utf8($row);
		print { $$r_handle } "\n";

		if(( defined $r_realms->{$index}{COUNTER_SON} ) && ( $r_realms->{$index}{COUNTER_SON} > 1 )) {
			log_it( LOG_DEBUG, "More than one son : $index" );
		
    } elsif(( defined $r_realms->{$index}{COUNTER_SON} ) && ( $r_realms->{$index}{COUNTER_SON} = 1 )) {
			# only one son
			log_it( LOG_DEBUG, "Only one son : $index" );

			# nothing print
			return 1;

		} elsif( ! defined $r_realms->{$index}{COUNTER_SON} ) {
			log_it( LOG_DEBUG, "Counter isn't defined : $index" );

		}
	}

	return 0;

}

# recursive function
sub sort_and_print {
  my $r_realms = shift;
	my $tree = shift;
	my $r_xml = shift;
	my $r_out_handle = shift;
	my $prefix = shift;
	my $lang = shift;
	my $type_desc = shift;
	my $print_empty = shift;

	# select nodes from this level
  my @nodes = $tree->children();

  # sort by $type_desc and language
	my @sorted = sort { sort_conf_data( $r_realms->{ $a->value }, $r_realms->{ $b->value }, $type_desc, $lang ) } @nodes;

	foreach my $node (@sorted) {
		my $deb_realm = $r_realms->{ $node->value };

		my $result = print_row( $r_realms, $r_xml, $node, $r_out_handle, $prefix, $lang, $type_desc, $print_empty);

		next if $result;  # only one son => don't print

	  sort_and_print( $r_realms, $node, $r_xml, $r_out_handle, $prefix."  ", $lang, $type_desc, $print_empty ) if ! $node->is_leaf;	
	}
}

# out dokuwiki - exported api
sub out_dokuwiki {
  my $r_realms = shift;  # config data
	my $tree = shift;  # tree depency
	my $out_file = shift;  # output file
	my $cachedir = shift;  # cache dir
	my $ext_cache = shift;  # cache file extension
	my $lang = shift;  # selected output language 
	my $type_desc = shift;  # selected output description ( orgname || acronym )
	my $print_empty = shift;  # print loc_names even without name

  

	# pre-read xml from cache
	my %xml = out_preread_xml( $r_realms, $cachedir, $ext_cache);  # xml data
	
	#add locations as containers
  get_loc_recursive(  $r_realms, \%xml, $lang, $print_empty, $tree );

	my $handle = new IO::File;
	open($handle, '>', $out_file) or log_die( "out_dokuwiki(): I can't open file ". $out_file ." for writing.");

	my $prefix = "  ";  # first prefix is empty
	
	sort_and_print( $r_realms, $tree, \%xml, \$handle, $prefix, $lang, $type_desc, $print_empty );

	close( $handle );
	
}


# END OF MODULE
1;
