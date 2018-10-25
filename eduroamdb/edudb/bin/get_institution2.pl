#!/usr/bin/perl -w

# $Id: get_institution.pl,v 1.33 2009-02-26 12:38:17 semik Exp $
#
# Skript collects data (institution.xml) from eduroam participants and
# generates whole NRO institution.xml file.
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
use AppConfig qw(:expand);
use POSIX qw(strftime);
use base 'HTTP::Message';
use HTTP::Request;
use HTTP::Headers;
use HTTP::Date;
use LWP::UserAgent;
use Data::Dumper;
use Sys::Syslog qw(:standard :macros);
use File::Copy;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
#use Tree;
#use locale;  # !!! locales !!!

use lib::LOG;
use lib::CONF_SHARED;
use lib::TREE_OPS;

use constant PROGRAM => 'get_institution.pl';
# text constants
use constant LOG_SUB_BEGIN => 'Sub entry point : ';
use constant LOG_SUB_END => 'Sub finish point : ';

# openlog options
use constant OPT_SYSLOG => 'nofatal';
use constant OPT_SYSLOG_STDERR => 'perror,nofatal';  # same out goes to syslog and std. error output

my $config = AppConfig->new
  ({
    GLOBAL     => { EXPAND => EXPAND_ALL, ARGCOUNT => 1 },
    CASE       => 1,
    CREATE     => '.*',
   },
   CFG                 => {DEFAULT => '../../get_institution.cfg'},
   CACHE_DIR           => {DEFAULT => '../cache' },
   EXT_CACHE           => {DEFAULT => '.cache' },
   EXT_LM              => {DEFAULT => '.lm' },
   WXS_INSTITUTION     => {DEFAULT => '../xsd/ver17042008/institution.xsd' },
   XML_ENCODING        => {DEFAULT => 'UTF-8' },
   XML_VERSION         => {DEFAULT => '1.0' },
   CONF_ENCODING        => { DEFAULT => 'UTF-8' },
   OUT_XML             => {DEFAULT => '/tmp/institution.xml' },
   OUT_TMP_XML         => {DEFAULT => '/tmp/institution.xml.tmp' },

   LOG_SYSLOG          => {DEFAULT => 1},
   LOG_LEVEL           => {DEFAULT => LOG_DEBUG },
   LOG_OPTS            => {DEFAULT => OPT_SYSLOG },
   LOG_STDOUT          => {DEFAULT => 1},
   COMMAND_DIFF        => {DEFAULT => '/usr/bin/diff' },  # path to diff
   DIFF_ARGS           => {DEFAULT => '-q' },  # arguments to diff

   ROOT                 => {DEFAULT => 'root' },  # root element of tree

   LANG                 => {DEFAULT => 'en'},  # default available language is english only
   REALM_RECORD         => {DEFAULT => 'org_name_'},

   FIX_CZECH_MESS      => {DEFAULT => undef},
  );

### subroutines section
# print help
sub print_help {
  print "Usage: convert_institution.pl [OPTIONS]\n";
  print "\t-CFG <file> - configuration file\n";
  print "\t-OUT_XML <file> - output xml file\n";
  print "\t-CACHE_DIR <directory> - directory with cached files\n";
  print "\t-CONF_ENCODING <encoding> - encoding of configuration file\n\n";
  print "\t-EXT_CACHE <extension> - extension of cached file\n";
  print "\t-WXS_INSTITUTION <xml_schema> - xml schema for validation\n";
  print "\t-XML_ENCODING <encoding> - encoding of xml cached files\n";
  print "\t-OUT_TMP_XML <file> - output temporary xml file\n";
  print "\t-LOG_SYSLOG [0|1] - program log to syslog\n";
  print "\t-LOG_LEVEL <log_level> - log level\n";
  print "\t-LOG_STDOUT [0|1] - program log to stdout\n";
  print "\t-LANG <lang> - output language\n";
  #print "\t-OUT_DESC <".lib::CONF_SHARED::ACRONYM."|".lib::CONF_SHARED::ORGNAME."> - description of institution used in output\n";
  print "\t-COMMAND_DIFF <path_to_diff> - path to diff\n";
}



# get_last_modified read all last_modified file
sub get_last_modified {
  my $CACHE_DIR = shift;
  my $r_realms = shift;
  my $ext_cache = shift;
  my $ext_ml = shift;
  my $realm;
  my %res;  #result hash

  foreach $realm (keys %$r_realms) {
    my $f_temp = $CACHE_DIR."/".$realm.$ext_ml;
    my $f_cache = $CACHE_DIR."/".$realm.$ext_cache;

    -f $f_temp or next;  # header last_modified file doesn't exist
    -f $f_cache or next;  # cache file doesn't exist

    open( F_TMP, $f_temp ) or next;  # can't open file for reading
    my $row = <F_TMP>; 
    # file exist but it is empty
    if ( ! defined $row ) {
      next;
    }
    $res{$realm} = $row;
    close( F_TMP );

    log_it( LOG_DEBUG, "get_last_modified(): Realm-id : ". $realm ." / last modified : ". $row );

  }

  return %res;
}

# validate document
sub validate_xml {
  my $schema = shift;
  my $doc = shift;

  eval {
    my $xmlschema = XML::LibXML::Schema->new( location => $schema );
		#my $parser = XML::LibXML->new;
		#my $doc    = $parser->parse_file($file);

    $xmlschema->validate($doc);
  };

  return $@;
}

sub update_ts {
  my $node = shift;
  my $ts = shift || 0;

  return if ($ts == 0);

  foreach my $tse (@{$node->getElementsByTagName('ts')}) {
    $tse->firstChild->setData(strftime("%Y-%m-%dT%H:%M:%S", localtime($ts)));
  };
};

sub kill_ts {
  my $node = shift;

  foreach my $tse (@{$node->getElementsByTagName('ts')}) {
    $tse->parentNode->removeChild($tse);
  };
};

# Bohuzel nektery instituce generuji TS kdykoliv se soubor stahne,
# takze musim pred sha1sum vyhazet ts
sub downloaded_diff_cached {
  my $filename = shift;
  my $doc = shift;

  return 1 unless (-f $filename);

  my $temp_doc = $doc->cloneNode(1);
  kill_ts($temp_doc);

  my $parser = XML::LibXML->new();
  my $cache_doc;
  eval {
    $cache_doc = $parser->parse_file($filename);
  };
  kill_ts($cache_doc);

  my $temp_sha1 = sha1_hex($temp_doc->toString) || '1';
  my $cache_sha1 = sha1_hex($cache_doc->toString) || '2';

  return 0 if ($temp_sha1 eq $cache_sha1);
  return 1;
};

# get_institution_xml gets institution.xml from url or from cache, when url isn't available
sub get_institution_xml {
  my $r_realms = shift;
  my $r_lm = shift;  # reference on last_modified hash
  my $CACHE_DIR = shift;
  my $ext_cache = shift;
  my $ext_ml = shift;
  my $wxs_institution = shift;
  my $fix_czech_mess = shift;

  my $ext_tmp = '.tmp';
  my $method = 'GET';
  my %res;  # result hash it contains filename of fresh institution.xml

  foreach my $realm (keys %$r_realms) {
    # we create new http request with/without last_modified header
    my $r_arr = $$r_realms{$realm};

    log_it(LOG_DEBUG, "Get realm : ". $realm );

#    if ($$r_arr{INST_XML} =~ /storage.skolnilogin.cz/) {
#	warn "$realm: >".$$r_arr{INST_XML}."<\n";
#    };

    if (! defined $$r_arr{INST_XML} ) {
      next;  # all institution without url is only container of organization units
    }

    my @args = ('-4', '-q', '--no-check-certificate', '-O -');

    if( $$r_lm{$realm} ) {
      # is filled only if cache file exist
      push(@args, '--header=\'If-Modified-Since: '.time2str($$r_lm{$realm}).'\'');
    }

    my $cmd = join(' ', 'wget', @args, $$r_arr{INST_XML});
    my $res = 0;
    my $content = '';
    if (open(WGET, $cmd.' |')) {
      $content = join('', <WGET>);
      close(WGET);

      if ($content eq '') {
	log_it(LOG_INFO, "get_institution_xml: Realm-id: $realm; http return code: 304 (empty wget output)");
      } else {
	$res = 1;
      };
    } else {
      log_it(LOG_INFO, "get_institution_xml: Realm-id: $realm; wget err: $!");
    };

    my $filename = $CACHE_DIR."/".$realm.$ext_cache;

    if ($res) {
      # we need save xml file as temporary file
      my $f_cache = $CACHE_DIR."/".$realm.$ext_cache.$ext_tmp;
      my $f_lm = $CACHE_DIR."/".$realm.$ext_ml;

      #open( F_CACHE_TMP, ">".$f_cache);  # open to write
      #print F_CACHE_TMP $response->content;
      #close( F_CACHE_TMP );

      my $parser = XML::LibXML->new();
      my $temp_doc;
      eval {
	$temp_doc = $parser->parse_string( $content );
      };
      unless ($@) { # The document was sucessfully parsed -> it is valid XML file
	if ($fix_czech_mess) {
	  fix_czech_ll($temp_doc);
	  fix_czech_sz($temp_doc);
	  fix_too_high_resolution($temp_doc);
	  fix_weird_formats($temp_doc);
	};

	#$temp_doc->toFile( $f_cache ); #???

	-f $wxs_institution or log_die( "XML schema: $wxs_institution: $!");

	# try to validate document
	my $err = validate_xml($wxs_institution, $temp_doc);
	unless ($err) {
	  # document is valid
	  # we can copy to cache directory and make last_modified mark
	  log_it(LOG_DEBUG,
		 "get_institution_xml: Downloaded document for realm-id: $realm is valid");

	  if (downloaded_diff_cached($filename, $temp_doc)) {
	    $temp_doc->toFile($filename) or
	      log_die(LOG_ERR, "get_institution_xml: Failed to store $filename: $!");

	    my $last_modified = time;
	    if (open(F_LM, ">".$f_lm)) {
	      print F_LM $last_modified;
	      close(F_LM);
	    } else {
	      log_it(LOG_ERR, "get_institution_xml: Failed to store timestamp $f_lm: $!");
	    };

	    update_ts($temp_doc, $r_lm->{$realm});

	    $res{$realm} = $temp_doc;
	    next;
	  } else {
	    # Zalogovat ze se stazena verze nelisi a nechat program
	    # natahnout tu z disku.
	    log_it(LOG_DEBUG, "get_institution_xml: Cached and downloaded versions are same: $filename");
	  };
	} else {
	  log_it(LOG_ERR,
		 "get_institution_xml: Downloaded document for realm-id: $realm isn't valid: $err");
	};
      } else {
	log_it(LOG_ERR, "get_institution_xml: Failed to parse downloaded document: ".$@);
      };
    };

    # This place could be reached because of several reasons:
    #   1) document wasn't modified since our last check
    #   2) downloaded document is not valid
    #   3) there was an error during download
    #
    # Try to use last xml from cache if it exists
    #
    if ( -f $filename) {
      # validate document
      my $parser = XML::LibXML->new();
      my $temp_doc;
      eval {
	$temp_doc = $parser->parse_file($filename);
      };
      unless ($@) {
	my $err = validate_xml( $wxs_institution, $temp_doc);
	unless ($err) {
	  log_it(LOG_DEBUG,
		 "get_institution_xml: Document from cache for realm-id $realm is valid");

	  update_ts($temp_doc, $r_lm->{$realm});
	  $res{$realm} = $temp_doc;
	} else {
	  log_it(LOG_ERR,
		 "get_institution_xml: Document from cache for realm-id: $realm isn't valid: $err");
	};
      } else {
	log_it(LOG_ERR, "get_institution_xml: Failed to parse file $filename from cache: ".$@);
      };
    } else {
      log_it(LOG_ERR, "get_institution_xml: Cache is missing $filename for realm-id $realm: $!");
    };
  };

  return %res;
}

# look for realm in list of allowed realms
sub lookfor_realm {
  my $res = shift;
  my $r_realms = shift;
  my $institution = shift;

  log_it( LOG_DEBUG, "lookfor_realm(): Realm-id : ". $institution ." contains <inst_realm> ". $res->textContent );
  my $r_arr = $$r_realms{$institution};
  my $r_2  = $$r_arr{REALM};
  my $pattern = $$r_arr{PATTERN};
  my $i = 0;
  foreach my $piece (@$r_2) {
   
    if( $pattern ) {
      # pattern match only
      if( $res->textContent =~ $pattern ) {
        log_it( LOG_DEBUG, "lookfor_realm(): pattern realm match");
        return 0;  # allowed
      }
    } else {
      # exact match
      if( $res->textContent eq $piece ) {
        log_it( LOG_DEBUG, "lookfor_realm(): exact realm match");
        return 0;  # allowed
      }
    }

  }

  log_it( LOG_DEBUG, "lookfor_realm(): realm \"".$res->textContent."\" do not match any of allowed realms: ".join(', ', map {"\"$_\""} @{$r_2}));
  return 1;  # not allowed

}

# check if all write about its realms
sub check_realm {
  my $root = shift;
  my $r_realms = shift;
  my $institution = shift;

  my @res = $root->getElementsByTagName( 'inst_realm' );
  foreach my $res (@res) {
    if(lookfor_realm( $res, $r_realms, $institution )) {
      return 1;  # not allowed
    }
  }
  return 0;
}

# Jan Tomasek: I did stupid mistake in example data for Czech
# institutions. I swapped longitude and latitude. Everyone copied that
# mistake from me :/ This function is trying to detect this problem
# and fix it. Other users of this script should not need this code.
#
sub fix_czech_ll {
  my $doc = shift;

  foreach my $location (@{$doc->getElementsByTagName('location')}) {
    my $longitude = ${$location->getElementsByTagName('longitude')}[0];
    my $latitude = ${$location->getElementsByTagName('latitude')}[0];

    my $lo_val = $longitude->textContent;
    my $la_val = $latitude->textContent;

    if (($lo_val =~ /^(51|50|49|48)/) and ($la_val =~ /^(11|12|13|14|15|16|17|18)/)) {
      $longitude->firstChild->setData($la_val);
      $latitude->firstChild->setData($lo_val);
    };
  };
};

sub fix_too_high_resolution {
  my $doc = shift;

  foreach my $coord (@{$doc->getElementsByTagName('longitude')},
		     @{$doc->getElementsByTagName('latitude')}) {
    my $coord_text = $coord->textContent;
    #if ($coord_text =~ /\.\d+\"(N|E)$/) {
    if ($coord_text =~ /^(\d+)°([0-9\.]+)\'(\d+)\.(\d{0,2})\d*"([E|N])/) {
      my $new = $coord_text;
      $new = "$1°$2'$3.$4\"$5";
      $coord->firstChild->setData($new);
      #warn "$coord_text -> $new\n";
    } elsif ($coord_text =~ /^(\d+)°([0-9\.]+)\'(\d+)"([E|N])/) {
	my $new = $coord_text;
	$new = "$1°$2'$3.00\"$4";
	$coord->firstChild->setData($new);
	#warn "$coord_text -> $new\n";
    };
  };
};

sub deg2dms {
    my $input = shift;

    my $deg = int($input);
    my $rest = $input-$deg;
    $input = 60*$rest;
    my $min = int($input);
    $rest = $input-$min;
    my $sec = 60*$rest;

    return sprintf("%d°%d'%.2f\"", $deg, $min, $sec);
};


sub fix_weird_formats {
  my $doc = shift;

  foreach my $coord (@{$doc->getElementsByTagName('longitude')},
		     @{$doc->getElementsByTagName('latitude')}) {
    my $coord_text = $coord->textContent;

    if ($coord_text =~ /\x{0094}/) {
      my $new = $coord_text;
      $new =~ s/\x{0094}/"/g;
	    $coord->firstChild->setData($new);
      warn "$coord_text -> $new\n";
    };
   
    if ($coord_text =~ /^([0-9.]+)(N|E)$/) {
	# Lon: 13.3702403E (180)
	# Lat: 49.7289725N (90) ... spatne, pismenko ma byt vzadu a musi to byt v DMS
	my $new = $coord_text;
	$new = deg2dms($1)."$2";
	$coord->firstChild->setData($new);
	#warn "$coord_text -> $new\n";
    } elsif ($coord_text =~ /^(N|E)([0-9.]+)$/) {
	# Lon: E13.3702403 (180)
	# Lat: N49.7289725 (90) ... spatne, musi to byt DMS
	my $new = $coord_text;
	$new = deg2dms($2)."$1";
	$coord->firstChild->setData($new);
	#warn "$coord_text -> $new\n";
    } elsif ($coord_text =~ /^([0-9.]+)°(N|E)$/) {
	# Lon: 17.265195°E (180)
	# Lat: 49.594309°N (90)
	my $new = $coord_text;
	$new = deg2dms($1)."$2";
	$coord->firstChild->setData($new);
	#warn "$coord_text -> $new\n";
    };
  };
};

# write big one institutions.xml
sub write_big_institution {
  my $r_insts = shift;  # hash of names of files with in xml
  my $f_out = shift;  # destionation xml file
  my $ver = shift;  # xml version
  my $encoding = shift;  # xml encoding
  my $r_realms = shift;  # allowed realms in institution.xml
  my $fix_czech_mess = shift; # try to detect swapped longitude & latitude ?

  my $doc_out = XML::LibXML::Document->new( $ver, $encoding );
  my $root_out = $doc_out->createElement( 'institutions' );
  $doc_out->setDocumentElement( $root_out );

  foreach my $institution (keys %$r_insts) {
    log_it(LOG_DEBUG, "write_big_institution: processing: $institution");
    my $docin = $$r_insts{$institution};
    my $root_in = $docin->documentElement;  # we should get <institutions> element
    # realm check
    if( check_realm( $root_in, $r_realms, $institution )) {
      log_it(LOG_ERR,
	     "write_big_institution: Skipping realm-id: $institution realm check problem occured");
      next;  # here is problem with realm
    }

    my @inst_in = $root_in->getElementsByTagName('institution');
    foreach my $inst_in (@inst_in) {
      # we add all as child to our destination xml
      $root_out->appendChild( $inst_in );
    }
  }

  if( -e $f_out ) {
    unlink $f_out or log_it( LOG_ERR, "write_big_institution(): Can't unlink out.xml");
  }
  $doc_out->toFile($f_out);  # some error checking? ;)
}

# compare two text file calling by diff utility
sub compare_file {
  my $command = shift;
  my $arg1 = shift;
  my $file1 = shift;
  my $file2 = shift;

  my @args = ( $command, $arg1, $file1, $file2 );
  system( @args ); # == 0 or log_it( LOG_ERR, "compare_file(): system @args failed: $?" );

  return $?;
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

# test if cache directory exists
-d $config->CACHE_DIR or
  log_die( "Cache directory ".$config->CACHE_DIR." doesn't exists : $!");
  
log_begin( PROGRAM, $config->LOG_OPTS, LOG_LOCAL0, $config->LOG_LEVEL, $config->LOG_SYSLOG, $config->LOG_STDOUT);

# read realms config
my %realms = get_realms_from_file( $config, $config->CONF_ENCODING ); # , $config->realms_cfg );

# create tree of institutions
my $tree =  create_tree_inst( \%realms, $config->ROOT );

debug_draw_tree( $tree );

# read cache
# we need last_modified from http header (it should be saved in <realm>.lm
my %last_modified = get_last_modified( $config->CACHE_DIR, \%realms, $config->EXT_CACHE, $config->EXT_LM );

# foreach realm gets institution.xml from url if last_modified changed
my %institutions = get_institution_xml( \%realms, \%last_modified, $config->CACHE_DIR, $config->EXT_CACHE, $config->EXT_LM, $config->WXS_INSTITUTION, $config->FIX_CZECH_MESS );

# we have all possible instituion.xml files, we need generate big one
write_big_institution( \%institutions, $config->OUT_TMP_XML, $config->XML_VERSION, $config->XML_ENCODING, \%realms , $config->FIX_CZECH_MESS);

# for sure revalidate result document
my $parser = XML::LibXML->new;
my $err = validate_xml( $config->WXS_INSTITUTION, $parser->parse_file($config->OUT_TMP_XML) );
if( $err ) {
  log_it(LOG_ERR, "Output XML \"".$config->OUT_TMP_XML."\" document isn't valid: $err");
} else {
  # store validated document in history
  my $history_filename = $config->OUT_XML.strftime ".%Y%m%d-%H%M%S", gmtime;
  if( -e $config->OUT_TMP_XML && -e $config->OUT_XML ) {
    # files exist, we can compare it
    if( compare_file( $config->COMMAND_DIFF, $config->DIFF_ARGS, $config->OUT_TMP_XML, $config->OUT_XML )) {
      my $cmd = sprintf("diff %s %s", $config->OUT_XML, $config->OUT_TMP_XML);
      warn `$cmd`;
      # files differ
      rename($config->OUT_TMP_XML, $config->OUT_XML)
	or log_it(LOG_ERR, "Can't rename temporary file \"".$config->OUT_TMP_XML.
		  "\" to output xml \"".$config->OUT_XML."\": $!");
      copy($config->OUT_XML, $history_filename)
	or log_it(LOG_ERR, "Can't create history file \"$history_filename\": $!");
      log_it(LOG_INFO, "New version of output XML \"".$config->OUT_XML."\" published.");
    } else {
      # delete tmp file
      unlink($config->OUT_TMP_XML);
      log_it(LOG_DEBUG, "No new version of output XML \"".$config->OUT_XML."\" available.");
    };
  } else {
    # files do no exist => we must create the first pair
    rename($config->OUT_TMP_XML, $config->OUT_XML)
      or log_it(LOG_ERR, "Can't rename temporary file \"".$config->OUT_TMP_XML.
		"\" to output xml \"".$config->OUT_XML."\": $!");
    copy($config->OUT_XML, $history_filename)
      or log_it(LOG_ERR, "Can't create history file: $!");
    log_it(LOG_INFO, "Output XML \"".$config->OUT_XML."\" published.");
  }
}

log_close();

