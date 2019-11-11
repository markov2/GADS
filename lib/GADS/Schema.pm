package GADS::Schema;
use parent 'DBIx::Class::Schema';

use strict;
use warnings;

use GADS::Layout ();

__PACKAGE__->load_namespaces;

our $VERSION = 76;

sub _add_column
{   my ($self, $rec_class, $col) = @_;
    my ($result_class, $linker) = $col->how_to_link_to_record($self);

    # We add each column twice, with a standard join and with an alternative
    # join. The alternative join allows correlated sub-queries to be used, with
    # the inner sub-query referencing a value from the main query.

    my $col_id  = $col->id;
    $rec_class->has_many("field${col_id}" => $result_class, $linker);
    $rec_class->has_many("field${col_id}_alternative" => $result_class, $linker);
}


sub setup
{   my ($self, $site) = @_;
    my $rec_class = $self->class('Record');

    $self->_add_column($rec_class, $_)
        for GADS::Layout->all_user_columns($site);

    $self;
}

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

# Add any new relationships for new fields. These are normally
# added when the field is created, but with multiple processes
# these will not have been created for the other processes.
# This subroutine checks for missing ones and adds them.

sub update_fields
{   my ($self, $site) = @_;

    my $newest = GADS::Layout->newest_field_id($site)
        or return; # No fields

    # up to date when 
    my $rec_rsource = $self->resultset('Record')->result_source;
    return if $rec_rsource->has_relationship("field$newest");

    my $rec_class = $self->class('Record');

    my $last_known = $newest -1;
	$last_known--
        until $last_known==0 || $rec_rsource->has_relationship("field$last_known");

    my $rs_layout = $self->resultset('Layout');

    for(my $field_id = $last_known+1; $field_id <= $newest; $field_id++) {
        my $col = $rs_layout->find($field_id)
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
