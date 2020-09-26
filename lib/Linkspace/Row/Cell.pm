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

sub datum    { $_[0]->{datum} ||= $_[0]->_instantiate_datum }

sub column   { $_[0]->{column} }
sub revision { $_[0]->{revision} }
sub row      { $_[0]->{row}   ||= $_[0]->revision->row }
sub sheet    { $_[0]->{sheet} ||= $_[0]->revision->sheet }
sub layout   { $_[0]->{layout}||= $_[0]->sheet->layout }

1;
