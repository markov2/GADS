=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package Linkspace::Row::Cell;

use warnings;
use strict;

use Log::Report 'linkspace';
use HTML::Entities    qw(encode_entities);

use Linkspace::Datum  ();

#XXX This really needs to be fast: I do not use Moo

=head1 NAME

Linkspace::Row::Cell - one datum in a sheet

=head1 DESCRIPTION

A cell is a object which connects a datum to its location: a row-revision
in a row in a sheet, with its content type.

B<WARNING> There are (potentially) zillion of datums, so on some places,
short-cuts are taken which break abstraction for the sake of performance.

=head1 METHODS: Constructors

=cut

# %args are
#     column       Linkspace::Column object
#     revision     Linkspace::Row::Revision object
#     datum        Linkspace::Datum object
#     datum_record HASH
# The datum can be specified as already prepared object, or as HASH raw
# from the database.

use overload
    '""' => 'as_string',
    bool => sub { ! $_[0]->is_blank };

sub new($%)
{   my ($class, %args) = @_;
    bless \%args, $class;
}

sub _cell_create($%)
{   my ($class, $insert, %args) = @_;
    my $column = $args{column} or panic;

    my $raw_values = delete $insert->{datums} || $column->default_values;
    $raw_values or return;

    my $datum_class = $column->datum_class;
    my $values = $datum_class->_unpack_values(undef, $raw_values, %args);

    my @datums;
    foreach my $value (@$values)
    {
    }

    $class->new(%args);
}

sub set_value($%)
{   my ($class, $raw_value) = (shift, shift);
    $class->set_values([ $raw_value ], @_);
}

sub set_values($%)
{   my ($self, $raw_values, %args) = @_;

    # An empty ARRAY means 'clean', missing means: no change.
    my $column = $self->column;

    error __"Cannot set this value as it is a parent value"
        if !$args{is_parent_value} && ! $column->can_child
        && $self->row->parent_id;

    my $datum_class = $column->datum_class;
    my @old_datums = @{$self->datums};
    my $values     = $datum_class->_unpack_values($self, $raw_values, %args);
    my @new_datums;

    foreach my $value (@$values)
    {   my $old = shift @old_datums;
        if($old && $old->value eq $value)    # reuse datum
        {   push @new_datums, $old;
            next;
        }
        push @new_datums, $datum_class->_datum_create($self, $value);
    }

    unless(@new_datums)
    {   #XXX do we really want to write blanks?  Blank is nothing so why store it?
        my $blank = $datum_class->field_value_blank;
        push @new_datums, $datum_class->_datum_create($self, $blank);
    }
}

sub text_all
{   my $self = shift;
    my $column = $self->column;
    [ map $column->datum_as_string($_), @{$self->datums} ];
}

sub as_string { join ', ', @{$_[0]->text_all} }

sub as_integer { $_[0]->{datums}[-1]->as_integer($_[0]) }

sub html {  encode_entities $_[0]->as_string }

sub html_form { $_[0]->text_all }

sub column   { $_[0]->{column} }
sub revision { $_[0]->{revision} }
sub row      { $_[0]->{row}    ||= $_[0]->revision->row }
sub sheet    { $_[0]->{sheet}  ||= $_[0]->revision->sheet }
sub layout   { $_[0]->{layout} ||= $_[0]->sheet->layout }

#-------------
=head1 METHODS: Handling datums

=head2 my $datum = $cell->datum;
Returns the datum which is kept in the cell.  Croaks when this is a
cell in a multivalue column.  May return C<undef> for a cell in a
column with optional values.
=cut

sub datum()
{   my $self = shift;
    ! $self->column->is_multivalue or panic;
    $self->{datums}[0];
}

=head2 \@datums = $cell->datums;
Returns all datums in this cell.  Also when this is not a multivalue
column, it still returns an ARRAY.
=cut

sub datums() { $_[0]->{datums} }

=head2 $cell->is_blank;
=cut

sub is_blank { ! @{$_[0]->{datums}} }

=head2 \@values = $cell->values;
Returns the values in all of the datums.
=cut

sub values { [ map $_->value, @{$_[0]->datums} ] }

=head2 \%h = $cell->for_code(%options);
Create a datastructure to pass column information to Calc logic.
Curcommon offers some options.

It is a pity, but the handling of multivalues is not consistent.
=cut

sub for_code(%)
{   my ($self, %args) = @_;

    my $datums = $self->datums;
    my @r = map $_->_value_for_code($self, $_, \%args), @$datums;

    if($datums->[0]->isa('Linkspace::Datum::Tree'))
    {   @r or push @r, +{  value => undef, parents => {} };
    }
    elsif($datums->[0]->isa('Linkspace::Datum::Enum'))
    {   return $self->column->is_multivalue
            ? +{ text => $self->as_string, values => \@r }
            : $self->as_string;
    }

    #XXX Not smart to pass multival datums in an inconsitent way.
    #XXX Kept for backwards compatibility.
    $self->column->is_multivalue && @r > 1 ? \@r : $r[0];
}

sub is_awaiting_approval { $_[0]->{is_awaiting_approval} }

sub datum_type
{   my $self  = shift;
    my $datum = $_[0]->{datums}[0];
    $datum && $datum->isa('Linkspace::Datum::Count') ? 'count' : $_[0]->column->type;
}

sub presentation
{   my $self   = shift;
    my $datums = $self->datums;
    my $show   = {
        type            => $self->datum_type,
        value           => $self->as_string,
        filter_value    => $self->filter_value,
        blank           => $self->is_blank,
        dependent_shown => $self->dependent_shown,
    };

    $_->presentation($show) for @$datums;
    $show;
}

sub filter_value
{   my $datum = ($_[0]->datums)[0];
    $datum ? $datum->filter_value : undef;
}

sub value_hash
{   my $self = shift;
    my $column = $self->column;
    my $type   = $column->type;

    if($type eq 'enum' || $type eq 'tree')
    {   my @hs = map $_->value_hash($column), @{$self->datums};
        #XXX Repacking usually a bad idea
        return +{
            ids     => [ map $_->{id}, @hs ],
            text    => [ map $_->{text}, @hs ],
            deleted => [ map $_->{deleted}, @hs ],
        };
    }

    panic;
}

sub deleted_values
{   my $self = shift;
    my $column = $self->column;

    if($column->type eq 'enum')
    {   return [ grep $_->{deleted}, map $_->value_hash($column), @{$self->datums} ];
    }
    panic;
}

# Most values are ids; this builds an index for them.
sub id_hash { +{ map +( $_->value => 1), @{$_[0]->datums} } }

# Tree
sub ids_as_params { join '&', map $_->value, @{$_[0]->datums} }

1;
