#!/usr/bin/perl -w

use strict;

package GPS2google;

use strict;
use Data::Dumper;
use XML::SAX::Base;
use Text::Iconv;
use vars qw(@ISA);
@ISA = qw(XML::SAX::Base);

my $e = Text::Iconv->new('utf-8', 'iso-8859-2');

sub start_element {
  my ($self, $el) = @_;

  if (($el->{Name} eq 'longitude') or
      ($el->{Name} eq 'latitude')) {
    $self->{element_name} = $el->{Name};
  };

  $self->SUPER::start_element( $el );
};

sub end_element {
  my ($self, $el) = @_;

  delete $self->{element_name};

  $self->SUPER::end_element( $el );
};


sub characters {
  my $self = shift;
  my $data = shift;

  if (defined($self->{element_name})) {
    if ($data->{Data} =~ /(\d*)\D+(\d*)\'*([0-9\.]*)/) {
      $data->{Data} = $1+($2+$3/60)/60;
    };
  };

  $self->SUPER::characters($data);
};

1;


package main;

use strict;

use XML::SAX::Machines qw(Pipeline);
use XML::SAX::Writer;
use Data::Dumper;

my $w = XML::SAX::Writer->new(
			      EncodeFrom => 'UTF-8',
			      EncodeTo => 'ISO-8859-2',
			      Output => \*STDOUT
			     );

my $m = Pipeline(GPS2google => $w);

my $fname = $ARGV[0];

#HEH??? na Etch to bylo nutne, na unstable neni.
print "<?xml version=\"1.0\" encoding=\"ISO-8859-2\"?>\n";

$m->parse_uri($fname);


