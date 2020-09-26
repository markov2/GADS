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

package Linkspace::Column::Date;
# Extended by ::Createddate

use Log::Report 'linkspace';

use Linkspace::Util  qw(iso2datetime);

use Moo;
extends 'Linkspace::Column';

my @options = (
   show_datepicker => 1,
   default_today   => 0,
);

### A date datum is either a date in the user's local time, or the text
#   CURDATE optionally with some seconds plus or minus.

###
### META
###

__PACKAGE__->register_type;

sub addable        { 1 }
sub can_multivalue { 1 }
sub has_multivalue_plus { 0 }
sub option_defaults { shift->SUPER::option_defaults(@_, @options) }
sub return_type    { 'date' }

### only for dates

sub include_time   { 0 }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Date => { layout_id => $col_id });
}

###
### Instance
###

sub show_datepicker
{   my $opt = $_[0]->options;  # option may be missing: then defaults to true
    exists $opt->{show_datepicker} ? $opt->{show_datepicker} : 1;
}

sub default_today { $_[0]->options->{default_today} // 0 }

sub _is_valid_value($%)
{   my ($self, $date, %options) = @_;

    $self->site->locale2dt($date)
        or error __x"Invalid date '{value}' for {col.name}. Please enter as {format}.",
             value => $date, col => $self, format => $self->site->locale->{date_pattern};

    $date;
}

sub validate_search
{   my ($self, $date, %args) = @_;
    !! $self->parse_date($date) && $self->SUPER::validate_search($date, %args);
}

#XXX move to datum
sub import_value
{   my ($self, $value) = @_;

    $::db->create(Date => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => iso2datetime($value->{value}),
    });
}

#XXX move to datum
sub field_values($;$%)
{   my ($self, $datum) = @_;
    my $values = $datum->values;

    map +{ value => $_ },
        @$values ? @$values : (undef); # No values, but still need to write null value
}

1;

