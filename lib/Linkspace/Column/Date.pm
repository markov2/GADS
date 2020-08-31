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
use GADS::View;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column';

my @option_names = qw/show_datepicker default_today/);

###
### META
###

INIT { __PACKAGE__->register_type }

sub addable        { 1 }
sub can_multivalue { 1 }
sub has_multivalue_plus { 0 }
sub option_names   { shift->SUPER::option_names(@_, @option_names_ }
sub return_type    { 'date' }

### only for dates

sub include_time   { 0 }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Date => { layout_id => $col_id });
}

###
### Instance
###

has show_datepicker => ( is => 'ro', default => sub { 1 } );
has default_today   => ( is => 'ro', default => sub { 0 } );

sub _is_valid_value($%)
{   my ($self, $date, %options) = @_;
    $self->parse_date($date)
        or error __x"Invalid date '{value}' for {col}. Please enter as {format}.",
             value => $date, col => $self->name, format => $self->dateformat;

    $date;
}

sub validate_search
{   my $self = shift;
    my ($value, %options) = @_;

    if(!$value)
    {   return 0 unless $options{fatal};
        error __x"Date cannot be blank for {col}.", col => $self->name;
    }

    return 1 if GADS::View->parse_date_filter($value);
    $self->validate($value, %options);
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Date => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => iso2datetime($value->{value}),
    });
}

sub field_values($;$%)
{   my ($self, $datum) = @_;
    my $values = $datum->values;

    map +{ value => $_ },
        @$values ? @$values : (undef); # No values, but still need to write null value
}

1;

