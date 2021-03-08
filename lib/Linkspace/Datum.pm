## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum;
use Log::Report 'linkspace';

use Linkspace::Util  qw(to_id);

test_session;

#!!! We cannot load the ::Datums packages here, because Moo will not be able to
#    inherit methods.  Booh!  Now in ::Row::Cell

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
    my @values = map $column->is_valid_value($_), grep length, @$values;
    @values ? [ map $class->new(column => $column, value => $_), @values ] : [];
}

=head2 $datum->write($revision, %args);
=cut

sub _create_insert(@) { shift; +{ @_ } }

sub write($%)
{   my ($self, $revision, %args) = @_;
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
    my %data = $rec->get_columns;
    $data{column_id} = delete $data{layout_id};
    $class->new(%data, @_);
}

sub from_id($%)
{   my ($class, $datum_id) = (shift, shift);
    my $rec = $::db->search($class->db_table => { id => $datum_id })->next;
    $rec ? $class->from_record($rec, @_) : undef;
}

=head2 \@datums = $class->datums_for_revision($revision);
Load all datums for a certain type of columns which belong to this C<$revision>.
For performance reasons, this loading is combined; the caller must take them
apart per columns.
=cut

sub datums_for_revision($%)
{   my ($class, $revision) = (shift, shift);
    [ map $class->from_record($_, revision => $revision),
         $::db->search($class->db_table => { record_id => to_id $revision })->all ];
}

#--------------------
=head1 METHODS: Attributes
=cut

has column_id    => ( is => 'rw' );  # only used during construction
has column       => ( is => 'rw' );  # only empty during construction
has value        => ( is => 'rw' );  # only empty during construction
has child_unique => ( is => 'ro', default  => 0 );
has revision     => ( is => 'rw' );

#--------------------
=head1 METHODS: Other
=cut

sub as_string    { $_[0]->column->datum_as_string($_[0]) }
sub as_integer   { panic "Not implemented" }
sub compare_as_string($)  { $_[0]->as_string cmp $_[1]->as_string }
sub compare_as_integer($) { $_[0]->as_integer cmp $_[1]->as_integer }
sub is_shown     { $_[0]->column->is_displayed_in($_[0]->revision) }

sub html_form    { $_[0]->value // '' }
sub filter_value { $_[0]->html_form }
sub match_value  { $_[0]->as_string }

# The value to search for unique values
sub search_values_unique { $_[0]->html_form }
sub html_withlinks { $_[0]->html }

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

sub _datum_delete($)
{   my ($self, $cell) = @_;
    $::db->delete($self->db_table,
      { record_id => $cell->revision->id,
        layout_id => $cell->column->id,
      });
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

# Curval and autocur support this.  Returns datums
sub derefs { [ shift ] }

sub sortable { $_[0]->as_string }

1;
