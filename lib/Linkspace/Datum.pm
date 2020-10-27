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

package Linkspace::Datum;
use Log::Report 'linkspace';

#use Linkspace::Datum::Autocur;
#use Linkspace::Datum::Calc;
use Linkspace::Datum::Count;
#use Linkspace::Datum::Curcommon;
#use Linkspace::Datum::Curval;
use Linkspace::Datum::Date;
use Linkspace::Datum::Daterange;
use Linkspace::Datum::Enum;
use Linkspace::Datum::File;
use Linkspace::Datum::ID;
use Linkspace::Datum::Integer;
use Linkspace::Datum::Person;
use Linkspace::Datum::Rag;
use Linkspace::Datum::Serial;
use Linkspace::Datum::String;
use Linkspace::Datum::Tree;

use Moo;

use overload
    bool  => sub { 1 },
    '""'  => 'as_string',
    '0+'  => 'as_integer',
    'cmp' => 'compare_values',
    fallback => 1;

# That value that will be used in an edit form to test the display of a
# display_field dependent field

sub value_regex_test { shift->text_all }

sub html_form    { $_[0]->value // '' }
sub filter_value { $_[0]->html_form }

# The values needed to pass to the set_values function of a datum. Normally the
# same as the HTML fields, but overridden where necessary
sub set_values   { shift->html_form }

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

sub as_string($) { $_[1]->datum_as_string($_[0]) }  # $self, $column

sub as_integer   { panic "Not implemented" }

1;
