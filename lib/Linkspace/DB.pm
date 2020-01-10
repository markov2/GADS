
package Linkspace::DB;

use warnings;
use strict;

use Log::Report 'linkspace';

# Close to all records in the database are restricted to a site.  However,
# only the top-level elements contain a direct reference to the site.  Other
# tables refer to indirectly to the site.

my %has_site_id = map +($_ => 1),
    qw/Audit Department Group Import Organisation Team Title Instance User/;

use Moo;
#use MooX::Types::MooseLike::Base qw/:all/;
use DBIx::Class::ResultClass::HashRefInflator;

=head1 NAME
Linkspace::DB - database abstraction

=head1 SYNOPSIS

  my $db = $::linkspace->db;
  my $schema = $db->schema;

=head1 DESCRIPTION

This module manages (DBIC-)schema controled database access.  It may
share the database connection with other instances.

One of these objects is the I<generic> database connection, which does
not know about the sheets.  Other objects will represent sheet sets (Sites)
which have extended rules in the Records.

=head1 METHODS: Constructors

=head1 METHODS: Attributes

=head2 my $schema = $db->schema;
Returns the L<Linkspace::Schema> object (extends L<DBIx::Class::Schema>)
which manages the database access.
=cut

has schema => (
    is       => 'ro',
    required => 1,
);


=head1 METHODS: Processing

=head2 my $guard = $db->begin_work;
Start a transaction.  You need to commit or rollback the guard when you
finish working.

  my $guard = $db->begin_work;
  # ... complex db work ....
  $guard->commit;
=cut

sub begin_work() { shift->schema->txn_scope_guard }


=head2 my $rs = $db->resultset($table);
=cut

sub resultset
{   my ($self, $table) = @_;
    my $rs = $self->{LD_rs}{$table} ||= $self->schema->resultset($table);
    $rs->search_rs({'me.site_id' => $::session->site->id}) if $has_site_id{$table};
    $rs;
}

=head2 my $results = $db->search($table, [ \%cond, [ \%attrs ]]);
Search for records in the C<$table>.  You may pass C<@more> parameters for
the search.

Simply use C<results_class = 'HASH'> in C<%attrs> when you mean
C<DBIx::Class::ResultClass::HashRefInflator>.
=cut

sub search
{   my ($self, $table, $cond, $attrs) = @_;

    $attrs->{result_class} = 'DBIx::Class::ResultClass::HashRefInflator'
        if $attrs && $attrs->{result_class} && $attrs->{result_class} eq 'HASH';

    $self->resultset($table)->search($cond, $attrs);
}

=head2 my $result = $db->get_record($table, $id);
Returns one result HASH.
=cut

sub get_record($$)
{   my ($self, $table, $id) = @_;
    $self->resultset($table)->single({id => $id});
}

=head2 my $result = $db->create($table, \%data);
Create a record in the C<$table>, containing C<%data>.
=cut

sub create($$)
{   my ($self, $table, $data) = @_;
    $data->{site_id} ||= $::session->site->id if $has_site_id{$table};
    $self->schema->resultset($table)->create($data);
}

=head2 $db->update($table, $id, \%changes);

=head2 $db->update($table, $object, \%changes);

=head2 $db->update($table, \%search, \%changes);

Update the record with C<$id> (or simple C<%search>) with the C<%changes>.
When an C<$object> is passed, it must have the C<$id> method.
=cut

sub update($$$)
{    my ($self, $table, $which, $data) = @_;
     my $search
        = ! ref $which   ? +{ id => $which }
        : blessed $which ? +{ id => $which->id }
        :                  $which;

     $self->resultset($table)->search($which)->update($data);
}

=head2 $db->delete($table, \%search);

=head2 $db->delete($table, $id);

Delete from C<$table> all matching records.
=cut

sub delete
{   my ($self, $table, $search) = (shift, shift, shift);
    $search = +{ id => $search } unless ref $search eq 'HASH';
    $self->resultset($table)->search($search, @_)->delete;
}


=head1 METHODS: Database time format parser

=head2 my $string = $db->format_date($dt);
=head2 my $string = $db->format_datetime($dt);
=head2 my $dt = $db->parse_date($string);
=head2 my $dt = $db->parse_datetime($string);
=cut


sub _datetime_parser {
   my ($self, $method, $value) = @_;
   defined $value or return;

   ($self->{LD_dtp} ||= $self->schema->storage->datetime_parser)
       ->$method($value);
}

sub format_date($)     { $_[0]->_datetime_parser(format_date     => $_[1]) }
sub format_datetime($) { $_[0]->_datetime_parser(format_datetime => $_[1]) }
sub parse_date($)      { $_[0]->_datetime_parser(parse_date      => $_[1]) }
sub parse_datetime($)  { $_[0]->_datetime_parser(parse_datetime  => $_[1]) }

1;
