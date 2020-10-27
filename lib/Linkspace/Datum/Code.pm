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

package Linkspace::Datum::Code;

use Data::Dumper;
use GADS::Safe;
use String::CamelCase qw(camelize); 
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

extends 'Linkspace::Datum';

has vars => (
    is      => 'lazy',
);

sub _build_vars
{   my $self = shift;
    # Ensure recurse-prevention information is passed onto curval/autocurs
    # within code values
    $self->record->values_by_shortname(
        already_seen_code => $self->already_seen_code,
        level             => $self->already_seen_level,
        names             => [$self->column->params],
    );
}

sub write_cache
{   my ($self, $table) = @_;

    my @values = sort @{$self->value} if defined $self->value->[0];

    # We are generally already in a transaction at this point, but
    # start another one just in case
    my $guard = $self->schema->txn_scope_guard;

    my $tablec = camelize $table;
    my $vfield = $self->column->value_field;

    # First see if the number of existing values is different to the number to
    # write. If it is, delete and start again
    my $rs = $self->schema->resultset($tablec)->search({
        record_id => $self->record_id,
        layout_id => $self->column->id,
    }, {
        order_by => "me.$vfield",
    });
    $rs->delete if @values != $rs->count;

    foreach my $value (@values)
    {
        my $row = $rs->next;

        if ($row)
        {
            if (!$self->equal($row->$vfield, $value))
            {
                my %blank = %{$self->column->blank_row};
                $row->update({ %blank, $vfield => $value });
            }
        }
        else {
            $self->schema->resultset($tablec)->create({
                record_id => $self->record_id,
                layout_id => $self->column->{id},
                $vfield   => $value,
            });
        }
    }
    while (my $row = $rs->next)
    {
        $row->delete;
    }
    $guard->commit;
    return \@values;
}

sub re_evaluate
{   my ($self, %options) = @_;
    return if $options{no_errors} && $self->column->return_type eq 'error';
    my $old = $self->value;
}

sub _build_value
{   my $self = shift;

    my $column = $self->column;
    my $code   = $column->code;

    my @values;

    if(my $iv = $self->init_value)
    {
        my @vs = map { ref $_ eq 'HASH' ? $_->{$column->value_field} : $_ } @$iv;

        @values = $column->return_type eq 'date' ? @vs
          :  map $::db->parse_date($_), @vs;
    }
    elsif (!$code)
    {
        # Nothing, $value stays undef
    }
    else
    {   my $return;
        try { $return = $column->eval($column->code, $self->vars) };
        if ($@ || $return->{error})
        {
            my $error = $@ ? $@->wasFatal->message->toString : $return->{error};
            warning __x"Failed to eval code for field \"{field}\": {error} (code: {code}, params: {params})",
                field => $column->name,
                error => $error, code => $return->{code} || $column->code, params => Dumper($self->vars);
            $return->{error} = 1;
        }

        @values = $self->convert_value($return); # Convert value as required by calc/rag
    }

    \@values;
}

1;
