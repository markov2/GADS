
#XXX For now kept in the GADS namespace, because the whole DB schema is
#XXX there.  You cannot specify a different base-name for the loaded
#XXX namespace.

package GADS::Schema;

use Log::Report 'linkspace';
use Tie::Cache ();
use DBIx::Class::ResultClass::HashRefInflator ();

use Linkspace::Sheet::Layout ();
use Linkspace::DBICProfiler  ();

use Moo;
use namespace::clean;
extends 'DBIx::Class::Schema';

# Load all classes which relate to the schema.
__PACKAGE__->load_namespaces;

our $VERSION = 76;

=head1 NAME
Linkspace::Schema - manage the database structure

=head1 SYNOPSIS

  my $schema = $::linkspace->db->schema;

=head1 DESCRIPTION
Manage the C<DBIx::Class::Schema>, which interfaces the database
structure.

=head1 METHODS: Constructors

=head2 my $schema = Linkspace::Schema->new(%options);
=cut

sub connect(%)
{   my $class = shift;
    my $self = $class->SUPER::connect(@_);

    my $storage = $self->storage;
    $storage->debugobj(Linkspace::DBICProfiler->new);
    $storage->debug(1);

    # Limit the cached connections to 100
    tie %{$storage->dbh->{CachedKids}}, 'Tie::Cache', 100;

    # There should never be exceptions from DBIC, so we want to panic them to
    # ensure they get notified at the correct level. Unfortunately, DBIC's internal
    # code uses exceptions, and if these are panic'ed then they are not caught
    # properly. Use this dirty hack for the moment, but I am told these part of
    # DBIC may change in the future.
    $self->exception_action(sub {
        die $_[0] if $_[0] =~ /^Unable to satisfy requested constraint/; # Expected
        panic @_; # Not expected
    });

    $self;
}
;

#----------------------
=head1 METHODS: Columns
The Record class of the schema is dynamic: fields get added based on the
columns of the sheets.
=cut

sub _add_column
{   my ($self, $rec_class, $raw_col) = @_;
    return if $raw_col->is_internal;

    my ($table, $linker) = Linkspace::Column->type2class($raw_col->type)
       ->how_to_link_to_record($self->id);

    # We add each column twice, with a standard join and with an alternative
    # join. The alternative join allows correlated sub-queries to be used, with
    # the inner sub-query referencing a value from the main query.

    my $col_id  = $raw_col->id;
    $rec_class->has_many("field${col_id}" => $table, $linker);
    $rec_class->has_many("field${col_id}_alternative" => $table, $linker);
}


sub setup_record_column_finder($)
{   my ($self, $raw_cols) = @_;
    my $rec_class = $self->class('Record');
    $self->_add_column($rec_class, $_) for @$raw_cols;
    $self;
}

=head2 $schema->add_column($col);
Add a single column accessor to the Record.
=cut

sub add_column
{   my ($self, $col) = @_;

    # Temporary hack
    # very inefficient and needs to go away when the rel options show up
    my $rec_class = $self->class('Record');
    $self->_add_column($rec_class, $col);

    #XXX why is this needed, and why twice?
    __PACKAGE__->unregister_source('Record');
    __PACKAGE__->register_class(Record => $rec_class);

    $self->unregister_source('Record');
    $self->register_class(Record => $rec_class);
}

=head2 $schema->update_fields($site);
Add any new relationships for new fields of a C<$site>. These are normally
added when the field is created, but with multiple processes these will
not have been created for the other processes.  This subroutine checks
for missing ones and adds them.
=cut

sub update_fields
{   my ($self, $site) = @_;

    my $newest = Linkspace::Sheet::Layout->newest_field_id($site)
        or return; # No fields

    # up to date when 
    my $rec_rsource = $self->resultset('Record')->result_source;
    return if $rec_rsource->has_relationship("field$newest");

    my $rec_class   = $self->class('Record');

    my $last_known  = $newest -1;
	$last_known--
        until $last_known==0
           || $rec_rsource->has_relationship("field$last_known");

    for(my $col_id = $last_known+1; $col_id <= $newest; $col_id++) {
        my $col = $::db->search(Layout => $col_id)
            or next;      # Column may have since been deleted

        $self->_add_column($rec_class, $col);
    }

    #XXX why is this needed, and why twice?
    __PACKAGE__->unregister_source('Record');
    __PACKAGE__->register_class(Record => $rec_class);

    $self->unregister_source('Record');
    $self->register_class(Record => $rec_class);
}

1;
