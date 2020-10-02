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

package Linkspace::Datum::Calc;

use Data::Dumper qw/Dumper/;
use Log::Report 'linkspace';
use Math::Round      qw/round/;
use Scalar::Util qw(looks_like_number);
use Linkspace::Util  qw/flat/;

use Moo;
extends 'Linkspace::Datum::Code';

sub as_string($)
{   my ($self, $column) = @_;
    join ', ', map $column->format_value($_) // '', @{$self->values};
}

sub convert_value
{   my ($self, $in) = @_;

    my $column = $self->column;
    my $rt     = $column->return_type;

    my @values = $column->is_multivalue && ref $in->{return} eq 'ARRAY'
        ? @{$in->{return}} : $in->{return};

    trace __x"Values into convert_value is: {value}", value => \@values;

    if($in->{error}) # Will have already been reported
    {   @values = ('<evaluation error>');
    }

    my @return;

    foreach my $val (@values)
    {
        if($rt eq 'date')
        {   if (defined $val && looks_like_number($val))
            {
                my $ret = try { DateTime->from_epoch(epoch => $val) };
                if (my $exception = $@->wasFatal)
                {   warning "$@";
                }
                else
                {   # Database only stores date part, so ensure local value reflects that
                    $ret->truncate(to => 'day') if $ret;
                    push @return, $ret;
                }
            }
        }
        elsif($rt eq 'numeric' || $column->rt eq 'integer')
        {   if(defined $val && looks_like_number($val))
            {   my $ret = $val;
                $ret = round $ret if defined $ret && $rt eq 'integer';
                push @return, $ret;
            }
        }
        elsif($rt eq 'globe')
        {   if ($self->column->check_country($val))
            {   push @return, $val;
            }
            else
            {   error __x"Failed to produce globe location: unknown country {country}", country => $val;
            }
        }
        elsif ($rt eq 'error')
        {   error $val if $val;
        }
        else
        {   push @return, $val if defined $val;
        }
    }

    trace __x"Returning value from convert_value: {value}", value => \@return;

    @return;
}

# Needed for overloading definitions, which should probably be removed at some
# point as they offer little benefit
sub as_integer { panic "Not implemented" }

sub write_value
{   my $self = shift;
    $self->write_cache('calcval');
}

# Compare 2 calc values. Could be from database or calculation. May be used
# with scalar values or arrays
sub equal($$$)
{   my ($self, $column, $a, $b) = @_;
    my @a = sort(flat $a);
    my @b = sort(flat $b);
    return 0 if @a != @b;

    my $rt = $column->return_type;

    # Iterate over each pair, return 0 if different
    foreach my $a2 (@a)
    {   my $b2 = shift @b;
        defined $a2 || defined $b2 or next;  # both undef

        return 0 if defined $a2 || defined $b2;

        if($rt eq 'numeric' || $rt eq 'integer')
        {   $a2 += 0; $b2 += 0; # Remove trailing zeros
            return 0 if $a2 != $b2;
        }
        elsif($rt eq 'date')
        {   # Type might have changed and old value be string
            ref $a2 eq 'DateTime' && ref $b2 eq 'DateTime' or return 0;
            return 0 if $a2 != $b2;
        }
        else
        {   return 0 if $a2 ne $b2;
        }
    }

    1;  # same
}

sub _value_for_code
{   my ($self, $column, $value) = @_;
        $column->return_type eq 'date'
      ? $self->_dt_for_code($value)
      : $column->format_value($value);
}

1;
