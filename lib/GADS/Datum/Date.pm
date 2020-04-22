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

package GADS::Datum::Date;

use DateTime;
use DateTime::Format::DateManip;
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

use Linkspace::Util qw/parse_duration/;

extends 'GADS::Datum';

after set_value => sub {
    my ($self, $all, %options) = @_;
    my @all = ref $all eq 'ARRAY' ? @$all : defined $all ? $all : ();
    shift @all if @all % 2 == 1 && !$all[0]; # First is hidden value from form

    my @values    = map $self->_to_dt($_, source => 'user', %options), @all;
    my @text_all  = sort map $self->_as_string($_), @values;
    my $old_texts = $self->text_all;

    if("@text_all" ne "@$old_texts")
    {   $self->changed(1);
        $self->_set_values(\@values);
        $self->_set_text_all(\@text_all);
    }

    my $clone = $self->clone;
    $self->oldvalue($clone);
};


has values => (
    is      => 'rwp',
    isa     => ArrayRef,
    lazy    => 1,
    coerce  => sub {
        my $values = shift;

        # If the timezone is floating, then assume it is UTC (e.g. from MySQL
        # database which do not have timezones stored). Set it as UTC, as
        # otherwise any changes to another timezone will not make any effect
        $_->time_zone->is_floating && $_->set_time_zone('UTC') for @$values;

        #XXX May want to support other timezones in the future
        $_->set_time_zone('Europe/London') for @$values;
        $values;
    },
    builder => sub {
        my $self = shift;

        return [ DateTime->now ]
            if $self->record && $self->record->new_entry
            && $self->column->default_today;

        my $iv = $self->init_value or return [];
        my @values = map $self->_to_dt($_, source => 'db'), @$iv;

        $self->has_value(!!@values);
        \@values;
    },
);

sub is_blank { ! grep $_, @{$_[0]->values} }

# Can't use predicate, as value may not have been built on
# second time it's set
has has_value => (
    is => 'rw',
);

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->($self, values => $self->values, @_);
};

sub _to_dt
{   my ($self, $value, %options) = @_;
    my $source = $options{source};
    $value = $value->{value} if ref $value eq 'HASH';
    $value or return;

    return $value->clone
        if ref $value eq 'DateTime';

    return $value =~ / / ? $::db->parse_datetime($value) : $::db->parse_date($value)
        if $source eq 'db';

    # Assume 'user'
    my $column = $self->column;

    if(!$column->validate($value) && $options{bulk}) # Only allow duration during bulk update
    {
        # See if it's a duration and return that instead if so
        if(my $duration = parse_duration $value)
        {   return map $_->clone->add_duration($duration), @{$self->values};
        }

        # Will bork below
    }

    $column->validate($value, fatal => 1);
    $column->parse_date($value);
}

has text_all => (
    is      => 'lazy',
    builder => sub { [ map $self->_as_string($_), @{$self->values} ] },
);

sub as_integer { panic "Not implemented" }
sub as_string { join ', ', @{$_[0]->text_all} }
sub html_form { $_[0]->text_all }

sub _as_string
{   my ($self, $value) = @_;

    $::session->user->dt2local($value, $self->column->dateformat,
       include_time => $self->column->include_time) || '';
}

sub _build_for_code
{   my $self = shift;

    return undef if !$self->column->is_multivalue && $self->is_blank;

    my @return = map $self->_date_for_code($_), @{$self->values};

    $self->column->is_multivalue || @return > 1 ? \@return : $return[0];
}

1;

