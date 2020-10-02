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

#XXX This really needs to be fast: I do not use Moo

package Linkspace::Row::Cell;

use warnings;
use strict;

use Log::Report 'linkspace';
use Linkspace::Datum  ();

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

use overload '""' => 'as_string';

sub new($%)
{   my ($class, %args) = @_;
    bless \%args, $class;
}

sub _cell_create($%)
{   my ($class, $insert, %args) = @_;

    my @datums = flat(delete $insert->{datums} || delete $insert->{datum});
    @datums or return;

    $args{column} or panic;
    $class->new(%args);
}

sub column   { $_[0]->{column} }
sub revision { $_[0]->{revision} }
sub row      { $_[0]->{row}   ||= $_[0]->revision->row }
sub sheet    { $_[0]->{sheet} ||= $_[0]->revision->sheet }
sub layout   { $_[0]->{layout}||= $_[0]->sheet->layout }

#-------------
=head1 METHODS: Handling datums

=head2 my $datum = $cell->datum;
Returns the datum which is kept in the cell.  Croaks when this is a
cell in a multivalue column.  May return C<undef> for a cell in a
column with optional values.
=cut

sub datum()
{   my $self = shift;
    ! $column->is_multivalue or panic;
    $self->{datums}[0];
}

=head2 \@datums = $cell->datums;
Returns all datums in this cell.  Also when this is not a multivalue
column, it still returns an ARRAY.
=cut

sub datums() { $_[0]->{datums} }

=head2 \%h = $datum->for_code(%options);
Create a datastructure to pass column information to Calc logic.
Curcommon offers some options.

It is a pity, but the handling of multivalues is not consistent.
=cut

sub for_code(%)
{   my ($self, %args) = @_;
    my $datums = $self->values;
    @$values or return undef;

    my @datums = @{$self->datums};
    my @r = map $_->_value_for_code($self, $_, \%args), @datums;

    if($datums[0]->isa('Linkspace::Datum::Tree'))
    {   @r or push @r, +{  value => undef, parents => {} };
    }
    elsif($datums[0]->isa('Linkspace::Datum::Enum'))
    {   return $self->column->is_multivalue
            ? +{ text => $self->as_string, values => \@r }
            : $self->as_string;
    }

    #XXX Not smart to pass multival datums in an inconsitent way
    $self->column->is_multivalue && @r > 1 ? \@r : $r[0];
}

has is_awaiting_approval => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

1;
