## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Daterange;

use Log::Report 'linkspace';

use DateTime;
use DateTime::Span;
use Scalar::Util    qw(blessed);

use Linkspace::Util qw(iso2datetime);

use Moo;
extends 'Linkspace::Column';

my @options = (
    show_datepicker => 0,
);

###
### META
###

__PACKAGE__->register_type;

sub datum_class      { 'Linkspace::Datum::Daterange' }
sub addable          { 1 }
sub can_multivalue   { 1 }
sub has_multivalue_plus { 1 }
sub option_defaults  { shift->SUPER::option_defaults(@_, @options) }
sub retrieve_fields  { [ qw/from to/ ] }
sub return_type      { 'daterange' }
sub sort_field       { 'from' }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Daterange => { layout_id => $col_id });
}

###
### Instance
###

# Still counts as string storage for search (value field is string)
sub string_storage { $_[0]->return_type eq 'string' }

sub show_datepicker { $_[0]->_options->{show_datepicker} }

sub is_valid_value($)
{   my ($self, $value, %options) = @_;
    return $value if blessed $value && $value->isa('DateTime::Span');

    my $from = $value->{from};
    my $to   = $value->{to};

    $from && $to
        or error __x"Please enter 2 date values for '{col}'", col => $self->name;

    my $from_dt = $self->parse_date($from)
        or error __x"Invalid start date {value} for {col}. Please enter as {format}.",
            value => $from, col => $self->name, format => $self->site->locale->{date_pattern};

    my $to_dt = $self->parse_date($to)
        or error __x"Invalid end date {value} for {col}. Please enter as {format}.",
            value => $to, col => $self->name, format => $self->site->locale->{date_pattern};

    DateTime->compare($from_dt, $to_dt) < 0
        or error __x"Start date must be before the end date for '{col}'",
            col => $self->name;

    DateTime::Span->new(start => $from_dt, end => $to_dt);
}

sub datum_as_string($)
{   my ($self, $datum) = @_;
    my $site  = $self->site;
    $site->dt2local($datum->from) . ' to ' . $site->dt2local($datum->to);
}

sub validate_search
{   my ($self, $value, %options) = @_;
    return 1 if !$value;
    if($options{single_only})
    {   return 1 if $self->parse_date($value);
        error __x"Invalid single date format '{value}' for {name}",
            value => $value, name => $self->name;
    }

    if($options{full_only})
    {   if(my $hash = $self->split($value))
        {   return $self->is_valid_value($hash, %options);
        }
        # Unable to split
        return 0 unless $options{fatal};
        error __x"Invalid full date format {value} for {name}. Please enter as {format}.",
            value => $value, name => $self->name, format => $self->layout->config->dateformat;
    }

    # Accept both formats. Normal date format used to validate searches
    return 1 if $self->parse_date($value);

    my $split = $self->split($value);
    return 1 if $split && $self->is_valid_value($split);

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

1;

