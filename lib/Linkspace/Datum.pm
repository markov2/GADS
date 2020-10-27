## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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
