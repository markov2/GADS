## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Date;
# Extended by ::Createddate

use Log::Report 'linkspace';
use DateTime         ();

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

sub datum_as_string($)
{   my ($self, $datum) = @_;
    $::session->site->dt2local($datum->value, include_time => $self->include_time);
}

sub show_datepicker
{   my $opt = $_[0]->_options;  # option may be missing: then defaults to true
    exists $opt->{show_datepicker} ? $opt->{show_datepicker} : 1;
}

sub default_today  { $_[0]->_options->{default_today} // 0 }

sub default_values { $_[0]->default_today ? [ DateTime->now ] : [] }

sub _is_valid_value($%)
{   my ($self, $date, %options) = @_;

    $self->site->local2dt('auto',$date)
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

1;

