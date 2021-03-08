## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Calc;

use Log::Report 'linkspace';

use Data::Dumper    qw/Dumper/;
use Math::Round     qw/round/;
use Scalar::Util    qw/looks_like_number/;

use Linkspace::Util qw/flat/;

use Moo;
extends 'Linkspace::Datum::Code';

sub db_table { 'Calcval' }

### 2021-02-22: columns in GADS::Schema::Result::Calcval
# id            record_id     value_int     value_text
# layout_id     value_date    value_numeric

# 1 = compile-time error
# 2 = runtime error
has is_error => ( is => 'rw', default => 0 );

sub error { $_[0]->is_error ? $_[0]->value_text : undef }

sub from_record($$%)
{   my ($class, $rec, %args) = @_;
    my $self = $class->SUPER::from_record($rec, %args);

    my $column = $args{column};
    my $ef     = $column->error_field;
    if($self->$ef +0)     # may be float 0.0
    {   $self->is_error(1);
    }
    else
    {   my $vf = $column->value_field;
        $self->value($self->$vf);
    }
    $self;
}

sub new_error($$%)
{   my ($class, $revision, $column, $rc, $error) = @_;
    $class->write($revision, $column, { $column->error_field => $rc, value_text => $error });
}

sub new_datum($$%)
{   my ($class, $revision, $column, $value) = @_;
    $class->write($revision, $column, {
        $column->error_field => 0,
        $column->value_field => $value,
    });
}

sub write($$$)
{   my ($class, $revision, $column, $insert) = @_;
    $insert->{record_id} = $revision->id;
    $insert->{layout_id} = $column->id;

    my $r = $::db->create($class->db_table, $insert);
    $class->from_id($r->id, revision => $revision, column => $column);
}

has value_int     => ( is => 'rw' );
has value_text    => ( is => 'rw' );
has value_date    => ( is => 'rw' );
has value_numeric => ( is => 'rw' );

# Needed for overloading definitions, which should probably be removed at some
# point as they offer little benefit
sub as_integer { panic "Not implemented" }

# Compare 2 calc values. Could be from database or calculation. May be used
# with scalar values or arrays
sub equal($$$)
{   my ($self, $column, $a, $b) = @_;
    my @a = sort flat($a);
    my @b = sort flat($b);
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
{   my ($self, $cell) = @_;
    my $column = $cell->column;
    $column->return_type eq 'date' ? $self->_dt_for_code($self->value) : $column->format_value($self->value);
}

1;
