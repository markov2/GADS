## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

