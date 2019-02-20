#!/usr/bin/perl -w

# $Id: convert_institution.pl,v 1.18 2009-03-16 20:38:53 polish Exp $
#
# Script convert institution.xml (for whole NRO) to diffrent output format (dokuwiki, google kml, gpx)
# 
#
# Copyright (c) 2008, CESNET, z.s.p.o.
# Authors: Pavel Polacek <pavel.polacek@ujep.cz>
#          Jan Tomasek <jan.tomasek@cesnet.cz>, <jan@tomasek.cz>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# See README and COPYING for more details.

use strict;
use XML::LibXML;
#use XML::LibXML::Reader;
use AppConfig qw(:expand);
use POSIX qw(strftime locale_h);
use Data::Dumper;
use Sys::Syslog qw(:standard :macros);
use File::Copy;
use Tree;
use IO::File;

use lib::LOG;
use lib::CONF_SHARED;
use lib::TREE_OPS;
use lib::OUT_DOKUWIKI;
use lib::OUT_GPX;
use lib::OUT_KML;

# international sorting
use locale;
use utf8;
use Unicode::String qw(utf8 latin1 utf16);

use constant PROGRAM => 'convert_institution.pl';
# text constants
use constant LOG_SUB_BEGIN => 'Sub entry point : ';
use constant LOG_SUB_END => 'Sub finish point : ';

# openlog options
use constant OPT_SYSLOG => 'nofatal';
use constant OPT_SYSLOG_STDERR => 'perror,nofatal';  # same out goes to syslog and std. error output

# output module selection
use constant OPTION_OUT_DOKUWIKI => 'dokuwiki';
use constant OPTION_OUT_GPX => 'gpx';
use constant OPTION_OUT_KML => 'kml';

# Attributes in xml document
use constant ATTR_LANG => 'lang';
my $element_inst_realm = 'inst_realm';
my $element_country = 'country';

my $config = AppConfig->new
  ({
    GLOBAL     => { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE       => 1,
    CREATE     => '.*',
   },
   CFG                 => {DEFAULT => '../../get_institution.cfg'},
	 EXT_CACHE           => {DEFAULT => '.json' },  # always use data from cache
   CACHE_DIR           => {DEFAULT => '../cache' },
   #WXS_INSTITUTION     => {DEFAULT => '../xsd/ver17042008/institution.xsd' },
   #XML_INSTITUTION     => {DEFAULT => '../../institution.xml'},
   XML_ENCODING        => {DEFAULT => 'UTF-8' },
   CONF_ENCODING        => { DEFAULT => 'UTF-8' },  # encoding of appconfig file
   XML_VERSION         => {DEFAULT => '1.0' },

   LOG_SYSLOG          => {DEFAULT => 1},
   LOG_LEVEL           => {DEFAULT => LOG_DEBUG },
   LOG_OPTS            => {DEFAULT => OPT_SYSLOG },
   LOG_STDOUT          => {DEFAULT => 1},

   ROOT                 => {DEFAULT => 'root' },  # root element of tree

	 # specific options to convert_institution.xml
   LANG                 => {DEFAULT => 'en'},  # default available language is english only
	 OUT_DESC	=> {DEFAULT => lib::CONF_SHARED::ACRONYM },
	 #IN_XML								=> {DEFAULT => '../../institution.xml' },
	 OUTFILE							=> {DEFAULT => 'vysl.out'},
   OUT_MODULE           => {DEFAULT => OPTION_OUT_DOKUWIKI },
   REALM_RECORD         => {DEFAULT => '.*_name_.*'},  # mandatory record to detecting realms in config
   TIDY_XML             => {DEFAULT => undef },
	 PRINT_EMPTY_LOCNAME  => {DEFAULT => 0},
  );

### subroutines section

# print help
sub print_help {
  print "Usage: convert_institution.pl [OPTIONS]\n";
  print "\t-CFG <file> - configuration file\n";
  print "\t-CONF_ENCODING <encoding> - encoding of configuration file\n";
  print "\t-CACHE_DIR <directory> - directory with cached files\n";
  print "\t-LANG <lang> - output language\n";
  print "\t-OUTFILE <file> - output file\n";
  print "\t-OUT_MODULE [".OPTION_OUT_DOKUWIKI."|".OPTION_OUT_GPX."|".OPTION_OUT_KML."] - output module dokuwiki, gpx or kml\n\n";
  print "\t-EXT_CACHE <extension> - extension of cached file\n";
  print "\t-XML_ENCODING <encoding> - encoding of xml cached files\n";
  print "\t-LOG_SYSLOG [0|1] - program log to syslog\n";
  print "\t-LOG_LEVEL <log_level> - log level\n";
  print "\t-LOG_STDOUT [0|1] - program log to stdout\n";
  print "\t-OUT_DESC <".lib::CONF_SHARED::ACRONYM."|".lib::CONF_SHARED::ORGNAME."> - description of institution used in output\n";
	print "\t-PRINT_EMPTY_LOCNAME [0|1] - print locnames even even without name of locality (valid only in dokuwiki\n";
}

# set locale 
sub switch_locale {
	my $lang = shift;
	my $codepage = shift;

	# !!! used locales must be defined on target OS
	my $locale = "en_US";
	if ($lang eq "cs") {
		$locale = "cs_CZ";
	}

	my $complete_locale = $locale .".". $codepage;
	setlocale( LC_ALL, $complete_locale );
	log_it(LOG_DEBUG, "locale all settings : ". setlocale(LC_ALL));
	log_it(LOG_ERR, "switch_locale(): switch to $complete_locale failed : ". setlocale(LC_ALL) ) if (setlocale(LC_ALL) ne $complete_locale );

	# numeric format should be in english convention
	setlocale( LC_NUMERIC, 'en_US' );
	log_it(LOG_DEBUG, "locale numeric : ". setlocale( LC_NUMERIC ));

}


# create convert table from  realm to realm-id
sub realm2realm_id {
  my $r_realms = shift;
  
  my %r2rid;  # output table

  foreach my $realm_id (keys %$r_realms) {
    my $r_arr = $$r_realms{$realm_id};

    my $r_2 = $$r_arr{REALM};

    foreach my $realm (@$r_2) {
      $r2rid{$realm} = $realm_id;
      log_it( LOG_DEBUG, "realm2realm_id(): realm-id :". $realm_id ." / realm :". $realm );
    }
  }
  return %r2rid; 
}

# create index to xml_data_old
sub create_index_xml {
	my $r_realms = shift;
	my $r_data = shift;

	foreach my $institution ( @$r_data ) {
		print $institution->{'org_name'} ."\n";
	}

}

# load xml document
sub load_xml_obsolete {
  my $filename = shift;

	my $xml = new XML::Simple;

	my $data = $xml->XMLin( $filename ) or log_die "load_xml_obsolete(): I can't process ". $filename;

	#print Dumper($data);

  return $data;
}

# debug process xml_data_old
sub debug_xml_data_old {
	my $r_data = shift;

	my $neco = $$r_data->{'institution'};

	foreach my $inst (@$neco) {
		print "!!!! dalsi zaznam\n";
		print Dumper( $inst->{'inst_realm'} );
	}
	
	#my $neco2 = $$r_data->{'institution'}[1]{'country'};
	#print Dumper( $neco2 );


	#print Dumper($$r_data);

}

# add xml_data_old to realm hash structure
sub add_xml_data_old {
	my $r_realm = shift;
	my $r_data = shift;
	my $r_r2rid = shift;

	my $neco = $$r_data->{'institution'};

	foreach my $inst (@$neco) {
		# print "!!!! dalsi zaznam\n";
		# print Dumper( $inst->{'inst_realm'} );
		my $realm = $inst->{'inst_realm'};
		my $index_realm = $r_r2rid->{ $realm };
		#print Dumper( $index_realm );
		#print Dumper( $r_realm->{ $index_realm } ); 
		$r_realm->{ $index_realm }{'xml'} = $inst if defined $index_realm;

	}
  
	#print "finalni dumper\n";
	#print Dumper( $r_realm );
	
	#my $neco2 = $$r_data->{'institution'}[1]{'country'};
	#print Dumper( $neco2 );


	#print Dumper($$r_data);

}
# show all data in %realm
sub debug_realms_data {
  my $r_realms = shift;

  foreach my $realm (keys %$r_realms) {
    log_it( LOG_DEBUG, "debug_realms_data(): realm_id = ". $realm );

    my $r_arr = $$r_realms{ $realm };
    foreach my $key (keys %$r_arr) {
      log_it( LOG_DEBUG, "debug_realms_data(): key = ". $key ." ; data = ". $$r_arr{ $key } );
    }

  }

}

### body section (main())

# print help if program hasn't program
if (scalar @ARGV == 0 ) {
  print_help;
  exit;
}

$config->args(\@ARGV) or
  log_die( "Can't parse cmdline args\n");
$config->file($config->CFG) or
  log_die( "Can't open config file \"".$config->CFG."\": $!");
log_begin( PROGRAM, $config->LOG_OPTS, LOG_LOCAL0, $config->LOG_LEVEL, $config->LOG_SYSLOG, $config->LOG_STDOUT);

switch_locale( $config->LANG, $config->XML_ENCODING );

# read realms config
my %realms = get_realms_from_file( $config, $config->CONF_ENCODING ); # , $config->realms_cfg );

# create tree of institutions
my $tree =  create_tree_inst( \%realms, $config->ROOT );

#debug_draw_tree( $tree );

if( $config->OUT_MODULE eq OPTION_OUT_DOKUWIKI ) {
  out_dokuwiki( \%realms, $tree, $config->OUTFILE, $config->CACHE_DIR, $config->EXT_CACHE, $config->LANG, $config->OUT_DESC, $config->PRINT_EMPTY_LOCNAME );
} elsif( $config->OUT_MODULE eq OPTION_OUT_GPX ) {
  out_gpx(\%realms, $tree, $config->OUTFILE, $config->CACHE_DIR, $config->EXT_CACHE, $config->LANG, $config->OUT_DESC, $config->XML_ENCODING, $config->TIDY_XML);
} elsif( $config->OUT_MODULE eq OPTION_OUT_KML ) {
  out_kml(\%realms, $tree, $config->OUTFILE, $config->CACHE_DIR, $config->EXT_CACHE, $config->LANG, $config->OUT_DESC, $config->XML_ENCODING, $config->TIDY_XML);
}

log_close();

