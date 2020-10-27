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

use warnings;
use strict;

package Linkspace::Datum::Rag;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum::Code';

sub convert_value
{   my ($self, $in) = @_;

    my $value = lc $in->{return};
    trace __x"Value into convert_value is: {value}", value => $value;

    my $return
      = $in->{error}       ? 'e_purple' # Will have already been reported
      : !$value            ? 'a_grey'
      : $value eq 'red'    ? 'b_red'
      : $value eq 'amber'  ? 'c_amber'
      : $value eq 'yellow' ? 'c_yellow'
      : $value eq 'green'  ? 'd_green'
      :                      'e_purple'; # Not expected

    trace "Returning value from convert_value: $return";
    $return;
}

sub write_value
{   my $self = shift;
    $self->write_cache('ragval');
}

# XXX Why is this needed? Error when creating new record otherwise
sub as_integer($) { $_[1]->column->code2rag_id($_[0]) }

sub as_string
{   my $self = shift;
    $self->_value_single // "";
}

sub equal
{   my ($self, $a, $b) = @_;
    # values can be multiple in ::Code but will only be single for RAG
    ($a) = @$a if ref $a eq 'ARRAY';
    ($b) = @$b if ref $b eq 'ARRAY';
    (defined $a xor defined $b)
        and return;
    !defined $a && !defined $b and return 1;
    $a eq $b;
}

#XXX Does not support multivalue: last grade only
sub presentation($$)
{   my ($self, $cell, $show) = @_;
    delete $show->{value};
    $show->{grade} = $cell->column->as_grade($self);
}

1;

