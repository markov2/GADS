# This module manages database access

package Linkspace::DB;

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
#use MooX::Types::MooseLike::Base qw/:all/;

=head1 NAME
Linkspace::DB - database abstraction

=head1 SYNOPSIS

  my $db = $::linkspace->db;

=head1 METHODS: Constructors

=cut

sub BUILD {
    my $self = shift;
    my $schema = $self->{schema} = 
    $self;
}

=head2 my $schema = $db->generic_schema;

=cut

has generic_schema => (
    is      => 'ro',
    builder => sub { GADS::Schema->new },
);


=head1 METHODS: searching

=head2 my $resultset = $db->resultset($table);

  my @sites = $db->resultset('Site')->all;

Most tables are site dependent.   In those cases, you very probably need:

  my @users = $site->resultset('Users')->all;

=cut

sub resultset {
    my ($self, $table) = @_;
    $self->generic_schema->resultset($table);
}

=head2 my $search = $db->search($table, @more);

Site independent search.  Short form of:

   $db->resultset($table)->search(@more);

=cut

sub search {
    my ($self, $table) = (shift, shift);
    $self->resultset($table)->search(@_);
}

1;
