# tree operations

package lib::TREE_OPS;

use strict;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&create_early_proc_children &insert_child &debug_draw_tree &create_tree_inst );

use Tree;
use Sys::Syslog qw(:standard :macros);
use lib::LOG;

# create early proccessed children - recursive function
sub create_early_proc_children {
  my $r_wait_for = shift;  # children to proccess
  my $realm = shift;  # parent realm
  my $r_known_realm = shift;

  log_it(LOG_DEBUG, "create_early_proc_children: parent realm: $realm");

  my %wait_for = %$r_wait_for;
  my %known_realm = %$r_known_realm;

  foreach my $son_realm (@{$wait_for{ $realm }}) {
    log_it(LOG_DEBUG, "son realm: $son_realm");
    my $child = Tree->new( $son_realm );
    my $parent = $known_realm{ $realm };
    $parent->add_child( $child );
    $known_realm{ $son_realm } = $child;
    log_it(LOG_DEBUG, "create son $son_realm links to parrent $realm");
    create_early_proc_children( \%wait_for, $son_realm, \%known_realm ) if defined $wait_for{ $son_realm };
  }
}

# insert new child element
sub insert_child {
  my $parent = shift;
  my $son_realm = shift;
  my $r_known_realm = shift;

  my $child = Tree->new( $son_realm );
  $parent->add_child( $child );

  $$r_known_realm = $child;
}

# draw tree - debug function
sub debug_draw_tree {
  my $tree = shift;

  return if $tree->is_leaf();

  my @nodes = $tree->traverse();

  foreach my $node (@nodes) {
    log_it(LOG_DEBUG, 'debug_draw_tree: '.$node->depth().' '.$node->value());
  }
}

# create tree of institution from config options
sub create_tree_inst {
  my $r_realms = shift;
  my $root_name = shift;
  my $realm;

  my $tree = Tree->new( $root_name );  # root of the tree
  my %known_realm;  # known realms, created in tree already
  my %wait_for;  # wait for element

  foreach $realm (keys %$r_realms) {
    my $r_arr = $$r_realms{$realm};

    # lookfor parrent
    my $parent = $$r_arr{PARENT};
    if (defined $parent ) {
      log_it(LOG_DEBUG, "$realm has parent: $parent");

      # look for parent
      if( defined $known_realm{ $parent } ) {
        # link to parent
        insert_child( $known_realm{ $parent }, $realm, \$known_realm{$realm} );
      } else {
        # wait for creating parent first
        push(@{$wait_for{ $parent }}, $realm );
        next;
      }
    } else {
      # link to root
      insert_child( $tree, $realm, \$known_realm{ $realm } );

      log_it(LOG_DEBUG, "$realm links to root of the tree");
    }

    # create early processed children
    create_early_proc_children( \%wait_for, $realm, \%known_realm ) if defined $wait_for{ $realm };

  }

  return $tree;
}




1;
