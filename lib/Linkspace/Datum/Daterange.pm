## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Daterange;

use Log::Report 'linkspace';

use DateTime        ();
use DateTime::Span  ();
use Scalar::Util    qw/blessed/;
use Linkspace::Util qw/parse_duration/;

use Moo;
extends 'Linkspace::Datum';

sub _datum_create($$%)
{   my ($class, $cell, $value) = (shift, shift, shift);
    my $span = $value->{value};
    $value->{start} = $span->start;
    $value->{end}   = $span->end;
    $value->{value} = $span->as_string;
    $class->SUPER::_datum_create($cell, $value, @_);
}

# Dateranges can be specified as
#   . DateTime::Span objects
#   . list of [ $from, $to ]
#   . list of pairs $from => $to
#   . duration wrt the current datums

sub _add_to_span($$$)
{   my ($span, $add_start, $add_end) = @_;
    DateTime::Span->from_datetimes(
        start => $span->start->clone->add_duration($add_start),
        end   => $span->end->clone->add_duration($add_end),
    );
}

sub _unpack_values($%)
{   my ($class, $cell, $values, %args) = @_;
    my $subtract = $args{subtract_days_end} || 0;

    my @values = @$values;
    if($cell && $args{bulk})
    {   my ($from, $to) = @values==1 && ref $values[0] eq 'ARRAY' ? @{$values[0]} : @values;
        if(my $begin_step = parse_duration $from)
        {   my $end_step  = parse_duration $to;
            return [ map _add_to_span($_, $begin_step, $end_step), @{$cell->values} ];
        }
    }

    my $to_dt;
    if(($args{source} // 'db') eq 'user')
    {   my $site = $::session->site;
        $to_dt = sub { blessed $_[0] && $_[0]->isa('DateTime') ? $_[0] : $site->local2dt(date => $_[0]) };
    }
    else
    {   $to_dt = sub { blessed $_[0] && $_[0]->isa('DateTime') ? $_[0] : $::db->parse_date($_[0]) };
    }

    my @ranges;
    while(@values)
    {   my $value = shift @values;
        my $range;
        if(blessed $value && $value->isa('DateTime::Span'))
        {   $range = $value;
        }
        elsif(ref $value eq 'ARRAY')
        {   $range = DateTime::Span->from_datetimes(
                start => $to_dt->($value->[0]),
                end   => $to_dt->($value->[1]),
            );
        }
        else
        {   $range = DateTime::Span->from_datetimes(
                start => $to_dt->($value),
                end   => $to_dt->(shift @values),
            );
        };

        $range->end->subtract(days => $subtract) if $subtract;
        push @ranges, $range;
    }

    \@ranges;
}

sub as_integer { $_[0]->value->start->epoch }

has html_form => (
    is      => 'lazy',
);

sub _build_html_form
{   my $self = shift;
    my $site = $::session->site;
    [ map +($site->dt2local($_->start), $site->dt2local($_->end)), @{$self->values} ];
}

sub filter_value   { $_[0]->text_all->[0] }
sub search_values_unique { $_[0]->text_all }

sub _value_for_code
{   my ($self, $cell, $value) = @_;
     +{ from  => $self->_dt_for_code($value->start),
        to    => $self->_dt_for_code($value->end),
        value => $self->_as_string($cell, $value),
      };
}

sub field_value($)
{   my $self = shift;
    +{ from => $self->start, to => $self->end, value => $self->as_string };
}

sub field_value_blank() { +{ from => undef, to => undef, value => undef } }

1;

