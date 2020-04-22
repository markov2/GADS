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

package GADS::Datum::Calc;

use Data::Dumper qw/Dumper/;
use Log::Report 'linkspace';
use Math::Round qw/round/;
use Moo;
use Scalar::Util qw(looks_like_number);
use namespace::clean;

extends 'GADS::Datum::Code';

sub as_string
{   my $self = shift;
    my (@return, $df, $dc);

    foreach my $value ( @{$self->value} )
    {   push @return,
            ! defined $value
          ? ''
          : ref $value eq 'DateTime'
          ? $::session->user->dt2local($value,$df //= $self->column->dateformat)
          : $self->column->return_type eq 'numeric'
          ? ( ($dc //= $self->column->decimal_places // 0)
            ? sprintf("%.${dc}f", $value)
            : ($value + 0)   # Remove trailing zeros
            )
          : $value;
    }

    join ', ', @return;
}

sub convert_value
{   my ($self, $in) = @_;

    my $column = $self->column;

    my @values = $column->is_multivalue && ref $in->{return} eq 'ARRAY'
        ? @{$in->{return}} : $in->{return};

    {  local $Data::Dumper::Indent = 0;
       trace __x"Values into convert_value is: {value}", value => Dumper(\@values);
    }

    if ($in->{error}) # Will have already been reported
    {   @values = ('<evaluation error>');
    }

    my @return;

    foreach my $val (@values)
    {
        if ($column->return_type eq "date")
        {
            if (defined $val && looks_like_number($val))
            {
                my $ret;
                try { $ret = DateTime->from_epoch(epoch => $val) };
                if (my $exception = $@->wasFatal)
                {
                    warning "$@";
                }
                else {
                    # Database only stores date part, so ensure local value reflects
                    # that
                    $ret->truncate(to => 'day') if $ret;
                    push @return, $ret;
                }
            }
        }
        elsif ($column->return_type eq 'numeric' || $column->return_type eq 'integer')
        {
            if (defined $val && looks_like_number($val))
            {
                my $ret = $val;
                $ret = round $ret if defined $ret && $column->return_type eq 'integer';
                push @return, $ret;
            }
        }
        elsif ($column->return_type eq 'globe')
        {
            if ($self->column->check_country($val))
            {
                push @return, $val;
            }
            else {
                mistake __x"Failed to produce globe location: unknown country {country}", country => $val;
            }
        }
        elsif ($column->return_type eq 'error')
        {
            error $val if $val;
        }
        else {
            push @return, $val if defined $val;
        }
    }

    no warnings "uninitialized";
    trace __x"Returning value from convert_value: {value}", value => Dumper(\@return);

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
sub equal
{   my ($self, $a, $b) = @_;
    my @a = ref $a eq 'ARRAY' ? @$a : ($a);
    my @b = ref $b eq 'ARRAY' ? @$b : ($b);
    @a = sort @a if defined $a[0];
    @b = sort @b if defined $b[0];
    return 0 if @a != @b;
    # Iterate over each pair, return 0 if different
    foreach my $a2 (@a)
    {
        my $b2 = shift @b;

        (defined $a2 xor defined $b2)
            and return 0;
        !defined $a2 && !defined $b2 and next; # Same
        my $rt = $self->column->return_type;
        if ($rt eq 'numeric' || $rt eq 'integer')
        {
            $a2 += 0; $b2 += 0; # Remove trailing zeros
            return 0 if $a2 != $b2;
        }
        elsif ($rt eq 'date')
        {
            # Type might have changed and old value be string
            ref $a2 eq 'DateTime' && ref $b2 eq 'DateTime' or return 0;
            return 0 if $a2 != $b2;
        }
        else {
            return 0 if $a2 ne $b2;
        }
    }
    # Assume same
    return 1;
}

sub _build_for_code
{   my $self = shift;
    my $rt   = $self->column->return_type;
    my $v    = $self->value;

    my @return
      = $rt eq 'date'    ? map $self->_date_for_code($_), @$v
      : $rt eq 'numeric' ? map $self->as_string + 0, @$v   #XXX??
      : $rt eq 'integer' ? map int($_ // 0), @$v
      : map +(defined ? "$_" : undef), @v

    $self->column->is_multivalue ? \@return : $return[0];
}

sub is_blank { ! length $_[0]->as_string }

1;
