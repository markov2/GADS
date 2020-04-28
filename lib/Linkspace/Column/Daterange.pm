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

package Linkspace::Column::Daterange;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column';

use DateTime;
use Log::Report 'linkspace';
use Linkspace::Util qw(iso2datetime);

my @options_names = qw/show_datepicker/;

###
### META
###

INIT { __PACKAGE__->register_type }

sub addable        { 1 }
sub can_multivalue { 1 }
sub has_multivalue_plus { 1 }
sub option_names   { shift->SUPER::option_names(@_, @option_names) }
sub retrieve_fields{ [ qw/from to/ ] }
sub return_type    { 'daterange' }
sub sort_field     { 'from' }

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    $::db->delete(Daterange => { layout_id => $col_id });
}

###
### Instance
###

# Still counts as string storage for search (value field is string)
sub string_storage { $_[0]->return_type eq 'string' }

has show_datepicker => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    coerce  => sub { $_[0] ? 1 : 0 },
    builder => sub {
        my $self = shift;
        return 0 unless $self->has_options;
        $self->options->{show_datepicker};
    },
    trigger => sub { $_[0]->reset_options },
);

sub is_valid_value($)
{   my ($self, $value, %options) = @_;
    return 1 if !$value;

    my $from = $value->{from};
    my $to   = $value->{to};
    return 1 if $from || $to;

    if($from xor $to)
    {   $options{fatal} or return 0;
        error __x"Please enter 2 date values for '{col}'", col => $self->name;
    }

    my ($from_dt, $to_dt);

    if($from && !($from_dt = $self->parse_date($from)))
    {   $options{fatal} or return 0;
        error __x"Invalid start date {value} for {col}. Please enter as {format}.",
            value => $from, col => $self->name, format => $self->dateformat;
    }

    if($to && !($to_dt = $self->parse_date($to)))
    {   $options{fatal} or return 0;
        error __x"Invalid end date {value} for {col}. Please enter as {format}.",
            value => $to, col => $self->name, format => $self->dateformat;
    }

    if(DateTime->compare($from_dt, $to_dt) == 1)
    {   $options{fatal} or return 0;
        error __x"Start date must be before the end date for '{col}'", col => $self->name;
    }

    1;
}

sub validate_search
{   my ($self, $value, %options) = @_;
    return 1 if !$value;
    if ($options{single_only})
    {
        return 1 if $self->parse_date($value);
        return 0 unless $options{fatal};
        error __x"Invalid single date format {value} for {name}",
            value => $value, name => $self->name;
    }
    if ($options{full_only})
    {
        if(my $hash = $self->split($value))
        {   return $self->validate($hash, %options);
        }
        # Unable to split
        return 0 unless $options{fatal};
        error __x"Invalid full date format {value} for {name}. Please enter as {format}.",
            value => $value, name => $self->name, format => $self->layout->config->dateformat;
    }
    # Accept both formats. Normal date format used to validate searches
    return 1 if $self->parse_date($value);

    my $split = $self->split($value);
    return 1 if $split && $self->validate($split);

    return 0 unless $options{fatal};
    error "Invalid format {value} for {name}",
        value => $value, name => $self->name;
}

sub split
{   my ($self, $value) = @_;
    my ($from, $to) = $value =~ /(.+) to (.+)/
        or return;

    $self->parse_date($from) && $self->parse_date($to)
        or return;

    return {
        from => $from,
        to   => $to,
    };
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Daterange => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        from         => iso2datetime($value->{from}),
        to           => iso2datetime($value->{to}),
        value        => $value->{value},
    });
}

sub field_values($$%)
{    my ($self, $datum) = @_;

     my @ranges = @{$datum->values};
     @ranges or return +{ from => undef, to => undef, value => undef };

     my @texts = @{$datum->text_all};

     map +{ from => $_->start, to => $_->end, value => shift @texts },
        @ranges;
}

1;

