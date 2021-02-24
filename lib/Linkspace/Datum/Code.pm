## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Code;

use Log::Report 'linkspace';

use Data::Dumper;
use String::CamelCase qw(camelize); 

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Datum';

has vars => (
    is      => 'lazy',
);

sub _build_vars
{   my $self = shift;
    # Ensure recurse-prevention information is passed onto curval/autocurs
    # within code values
    $self->values_by_shortname($self->record,
        already_seen_code => $self->already_seen_code,
        level             => $self->already_seen_level,
        names             => [ $self->column->params ],
    );
}

sub values_by_shortname
{   my ($self, $row, %args) = @_;
    my $names = $args{names};

    my %index;
    foreach my $name (@$names)
    {   my $col   = $self->layout->column($name) or panic $name;
        my $cell  = $row->cell($col);
        my $linked = $col->link_parent;

        my $cell_base
           = $cell->is_awaiting_approval ? $cell->old_values
           : $linked && $cell->old_values # linked, and value overwritten
           ? $cell->oldvalue
           : $cell;

        # Retain and provide recurse-prevention information. See further
        # comments in Linkspace::Column::Curcommon
        my $already_seen_code = $args{already_seen_code};
        $already_seen_code->{$col->id} = $args{level};

        $index{$name} = $cell_base->for_code(
           already_seen_code  => $already_seen_code,
           already_seen_level => $args{level} + ($col->is_curcommon ? 1 : 0),
        );
    };
    \%index;
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

        if($row)
        {
            if(!$self->equal($row->$vfield, $value))
            {   my %blank = %{$self->column->blank_row};
                $row->update({ %blank, $vfield => $value });
            }
        }
        else
        {   $self->schema->resultset($tablec)->create({
                record_id => $self->record_id,
                layout_id => $self->column->{id},
                $vfield   => $value,
            });
        }
    }
    while(my $row = $rs->next)
    {   $row->delete;
    }
    $guard->commit;
    \@values;
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
        try { $return = $column->evaluate($column->code, $self->vars) };
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
