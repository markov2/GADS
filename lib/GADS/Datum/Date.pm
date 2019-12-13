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
    $all ||= [];
    $all = [$all] if ref $all ne 'ARRAY';
    my @all = @$all; # Take a copy first
    my $clone = $self->clone;
    shift @all if @all % 2 == 1 && !$all[0]; # First is hidden value from form
    my @values;
    while (@all)
    {
        my @dt = $self->_to_dt(shift @all, source => 'user', %options);
        push @values, @dt if @dt;
    }
    my @text_all = sort map { $self->_as_string($_) } @values;
    my @old_texts = @{$self->text_all};
    my $changed = "@text_all" ne "@old_texts";
    if ($changed)
    {
        $self->changed(1);
        $self->_set_values([@values]);
        $self->_set_text_all([@text_all]);
        $self->clear_html_form;
        $self->clear_blank;
    }
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
        $_->time_zone->is_floating && $_->set_time_zone('UTC') foreach @$values;
        # May want to support other timezones in the future
        $_->set_time_zone('Europe/London') foreach @$values;
        return $values;
    },
    builder => sub {
        my $self = shift;
        if ($self->record && $self->record->new_entry && $self->column->default_today)
        {
            return [DateTime->now];
        }
        $self->init_value or return [];
        my @values = map { $self->_to_dt($_, source => 'db') } @{$self->init_value};
        $self->has_value(!!@values);
        [@values];
    },
);

sub _build_blank
{   my $self = shift;
    ! grep { $_ } @{$self->values};
}


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

    if(ref $value eq 'DateTime')
    {   return $value->clone;
    }
    elsif($source eq 'db')
    {   return $value =~ / / ? $::db->parse_datetime($value) : $::db->parse_date($value);
    }
    else { # Assume 'user'
        if (!$self->column->validate($value) && $options{bulk}) # Only allow duration during bulk update
        {
            # See if it's a duration and return that instead if so
            if(my $duration = parse_duration $value)
            {   return map $_->clone->add_duration($duration), @{$self->values};
            }
            else {
                # Will bork below
            }
        }
        $self->column->validate($value, fatal => 1);
        $self->column->parse_date($value);
    }
}

has text_all => (
    is      => 'rwp',
    isa     => ArrayRef,
    lazy    => 1,
    builder => sub {
        my $self = shift;
        [ map { $self->_as_string($_) } @{$self->values} ];
    },
);

sub as_integer { panic "Not implemented" }

sub _as_string
{   my ($self, $value) = @_;

    $::session->user->dt2local($value, $self->column->dateformat,
       include_time => $self->column->include_time) || '';
}

sub as_string
{   my $self = shift;
    join ', ', @{$self->text_all};
}

has html_form => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_html_form
{   my $self = shift;
    [ map { $self->_as_string($_) } @{$self->values} ];
}

sub _build_for_code
{   my $self = shift;

    return undef if !$self->column->multivalue && $self->blank;

    my @return = map {
        $self->_date_for_code($_)
    } @{$self->values};

    $self->column->multivalue || @return > 1 ? \@return : $return[0];
}

1;

