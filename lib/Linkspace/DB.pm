
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

=head1 DESCRIPTION

This module manages (DBIC-)schema controled database access.  It may
share the database connection with other instances.

One of these objects is the I<generic> database connection, which does
not know about the sheets.  Other objects will represent sheet sets (Sites)
which have extended rules in the Records.

=head1 METHODS: Constructors

=head1 METHODS: attributes

=head2 my $schema = $db->schema;

=cut

has schema => (
    is       => 'ro',
    required => 1,
);


=head1 METHODS: searching

=head2 my $resultset = $db->resultset($table);

  my @sites = $db->resultset('Site')->all;

Most tables are site dependent. In those cases, you very probably need:

  my @users = $site->resultset('Users')->all;

=cut

sub resultset {
    my ($self, $table) = @_;
    $self->schema->resultset($table);
}

=head2 my $search = $db->search($table, @more);

Site independent search.  Short form of:

   $db->resultset($table)->search(@more);

=cut

sub search {
    my ($self, $table) = (shift, shift);
    $self->schema->resultset($table)->search(@_);
}

1;
