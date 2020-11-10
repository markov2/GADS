## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum;
use Log::Report 'linkspace';

use Linkspace::Util  qw(to_id);

#!!! We cannot load the ::Datums packages here, because Moo will not be able to
#    inherit methods.  Booh!

use Moo;

my @cache_tables = qw/Ragval Calcval/;
my @value_tables = qw/Enum String Intgr Daterange Date Person File Curval/;

use overload
    bool  => sub { 1 },
    '""'  => 'as_string',
    '0+'  => 'as_integer',
    'cmp' => 'compare_as_string',
    '<=>' => 'compare_as_integer',
    fallback => 1;

#--------------------
=head1 METHODS: Constructors

=head2 \@datums = $class->datums_prepare($column, \@values, $old);
Creating new cells is a two phase process: first the new cell in created have,
the it gets written.
=cut

sub datums_prepare($$$%)
{   my ($class, $column, $raw_values, $old_datums) = @_;
    my $values = $class->_unpack_values($column, $old_datums, $raw_values);

    #XXX column->is_valid_value() is doing too much
    my @values = map $column->_is_valid_value($_), @$values;
    [ map $class->new(column => $column, value => $_), @$values ];
}

=head2 $datum->write($revision, %args);
=cut

sub _create_insert(@) { shift; +{ @_ } }

sub write($%)
{    my ($self, $revision, %args) = @_;
     my $column = $self->column;

     my $insert = $self->_create_insert(
         record_id    => $revision->id,
         layout_id    => $column->id,
         child_unique => $args{child_unique} ? 1 : 0,
         value        => $self->value,
     );

     my $r = $::db->create($self->db_table, $insert);
     (ref $self)->from_id($r->id, revision => $revision, column => $column);
}

sub from_record($%)
{   my ($class, $rec) = (shift, shift);
    $class->new($rec->get_columns, @_);
}

sub from_id($%)
{   my ($class, $datum_id) = (shift, shift);
    my $rec = $::db->search($class->db_table => { id => $datum_id })->next;
    $rec ? $class->from_record($rec, @_) : undef;
}

=head2 \@recs = $column->records_for_revision($revision);
Load the records for this column which is on the C<$revision>.

For performance reasons, this will also return records of other columns
in the same row.  The caller must take them apart.
=cut

sub records_for_revision($%)
{   my ($class, $revision) = (shift, shift);
    [ $::db->search($class->db_table => { record_id => to_id $revision })->all ];
}

#--------------------
=head1 METHODS: Attributes
=cut

has column => ( is => 'ro', required => 1 );
has value  => ( is => 'ro', required => 1 );

has child_unique => ( is => 'ro', default => 0 );
has revision => ( is => 'rw' );

#--------------------
=head1 METHODS: Other
=cut

sub as_string  { $_[0]->column->datum_as_string($_[0]) }
sub as_integer { panic "Not implemented" }
sub compare_as_string($)  { $_[0]->as_string cmp $_[1]->as_string }
sub compare_as_integer($) { $_[0]->as_integer cmp $_[1]->as_integer }

# That value that will be used in an edit form to test the display of a
# display_field dependent field

sub value_regex_test { shift->text_all }

sub html_form    { $_[0]->value // '' }
sub filter_value { $_[0]->html_form }

# The value to search for unique values
sub search_values_unique { $_[0]->html_form }
sub html_withlinks { $_[0]->html }

sub dependent_shown
{   my $self    = shift;
    my $filter  = $self->column->display_field or return 0;
    $filter->show_field($self->record->fields, $self);
}

# Used by $cell->for_code
sub _value_for_code($$) { $_[0]->as_string }

sub _dt_for_code($)
{   my $dt = $_[1] or return undef;

    +{
        year   => $dt->year,
        month  => $dt->month,
        day    => $dt->day,
        hour   => $dt->hour,
        minute => $dt->minute,
        second => $dt->second,
        yday   => $dt->doy,
        epoch  => $dt->epoch,
    };
}

sub _datum_create($$%)
{   my ($class, $cell, $insert) = @_;
    $insert->{record_id} = $cell->revision->id;
    $insert->{layout_id} = $cell->column->id;
    my $r = $::db->create($class->db_table => $insert);
    $class->from_id($r->id);
}

sub field_value() { +{ value => $_[0]->value } }

sub field_value_blank() { +{ value => undef } }

sub has_values_stored_for($)
{   my ($self, $revision) = @_;
    my $search = { record_id => to_id $revision };
    foreach my $table (@value_tables)
    {   return 1 if $::db->search($table => $search)->count;
    }
    0;
}

sub remove_values_stored_for($)
{   my ($self, $revision) = @_;
    my $search = { record_id => to_id $revision };
    $::db->delete($_ => $search) for @value_tables, @cache_tables;
}

1;
