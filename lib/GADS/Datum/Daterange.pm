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

package GADS::Datum::Daterange;

use DateTime;
use DateTime::Format::DateManip;
use DateTime::Span;
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Datum';

# Set datum value with value from user
after set_value => sub {
    my ($self, $all, %options) = @_;
    $all ||= [];
    my @all = @$all; # Take a copy first
    my $clone = $self->clone;
    shift @all if @all % 2 == 1 && !$all[0]; # First is hidden value from form
    my @values;
    while (@all)
    {
        # Allow multiple sets of dateranges to be submitted in array ref blocks
        # or as one long array, 2 elements per range
        my $first = shift @all;
        my ($start, $end) = ref $first eq 'ARRAY' ? @$first : ($first, shift @all);
        my @dt = $self->_parse_dt([$start, $end], source => 'user', %options);
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
    builder => sub {
        my $self = shift;
        $self->init_value or return [];
        my @values = map { $self->_parse_dt($_, source => 'db') } @{$self->init_value};
        $self->has_value(!!@values);
        [@values];
    },
);

has text_all => (
    is      => 'rwp',
    isa     => ArrayRef,
    lazy    => 1,
    builder => sub {
        my $self = shift;
        [ map { $self->_as_string($_) } @{$self->values} ];
    },
);

sub _build_blank
{   my $self = shift;
    ! grep { $_->start && $_->end } @{$self->values};
}

# Can't use predicate, as value may not have been built on
# second time it's set
has has_value => (
    is => 'rw',
);

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->(
        $self,
        values => $self->values,
        @_,
    );
};

sub _parse_dt
{   my ($self, $original, %options) = @_;
    my $source = $options{source};

    $original or return;

    # Array ref will be received from form
    if (ref $original eq 'ARRAY')
    {
        $original = {
            from => $original->[0],
            to   => $original->[1],
        };
    }
    elsif (!ref $original)
    {
        # XXX Nasty hack. Would be better to pull both values from DB
        $original =~ /^([-0-9]+) to ([-0-9]+)$/;
        $original = {
            from => $1,
            to   => $2,
        };
    }

    # Otherwise assume it's a hashref: { from => .., to => .. }

    if (!$original->{from} && !$original->{to})
    {
        return;
    }

    my ($from, $to);
    if ($source eq 'db')
    {
        my $db_parser = session->site->schema->storage->datetime_parser;
        $from = $db_parser->parse_date($original->{from});
        $to   = $db_parser->parse_date($original->{to});
    }
    else { # Assume 'user'
        # If it's not a valid value, see if it's a duration instead (only for bulk)
        if ($self->column->validate($original, fatal => !$options{bulk}))
        {
            $from = $self->column->parse_date($original->{from});
            $to   = $self->column->parse_date($original->{to});
        }
        elsif($options{bulk}) {
            my $from_duration = DateTime::Format::DateManip->parse_duration($original->{from});
            my $to_duration = DateTime::Format::DateManip->parse_duration($original->{to});
            if ($from_duration || $to_duration)
            {
                if (@{$self->values})
                {
                    my @return;
                    foreach my $value (@{$self->values})
                    {
                        $from = $value->start;
                        $from->add_duration($from_duration) if $from_duration;
                        $to = $value->end;
                        $to->add_duration($to_duration) if $to_duration;
                        push @return, DateTime::Span->from_datetimes(start => $from, end => $to);
                    }
                    return @return;
                }
                else {
                    return; # Don't bork as we might be bulk updating, with some blank values
                }
            }
            else {
                # Nothing fits, raise fatal error
                $self->column->validate($original, fatal => 1);
            }
        }
    }

    $to->subtract( days => $options{subtract_days_end} ) if $options{subtract_days_end};
    (DateTime::Span->from_datetimes(start => $from, end => $to));
}

# XXX Why is this needed? Error when creating new record otherwise
sub as_integer
{   my $self = shift;
    $self->value; # Force update of values
    $self->value && $self->value->start ? $self->value->start->epoch : 0;
}

sub as_string
{   my $self = shift;
    join ', ', @{$self->text_all};
}

sub _as_string
{   my ($self, $range) = @_;
    $range && (my $start = $range->start) && (my $end = $range->end)
        or return '';

    my $format = $self->column->dateformat;
    my $user   = $::session->user;
    $user->dt2local($start, $format) . ' to ' . $user->dt2local($end);
}

has html_form => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_html_form
{   my $self = shift;
    my $format = $self->column->dateformat;
    my $user   = $::session->user;

    [ map +( $user->dt2local($_->start, $format)
           , $user->dt2local($_->end, $format) ) @{$self->values} ];
}

sub filter_value
{   shift->text_all->[0];
}

sub search_values_unique
{   shift->text_all;
}

sub _build_for_code
{   my $self = shift;
    return undef if !$self->column->multivalue && $self->blank;
    my @return = map {
        +{
            from  => $self->_date_for_code($_->start),
            to    => $self->_date_for_code($_->end),
            value => $self->_as_string($_),
        };
    } @{$self->values};

    $self->column->multivalue || @return > 1 ? \@return : $return[0];
}

1;

