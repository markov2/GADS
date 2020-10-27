## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Autocur;

use Log::Report 'linkspace';
use HTML::Entities qw/encode_entities/;

use Moo;
extends 'Linkspace::Datum::Curcommon';

sub _transform_value
{   my ($self, $value) = @_;
    my ($record, $id);

    if (!$value || (ref $value eq 'HASH' && !keys %$value))
    {
        # Do nothing
    }
    elsif (!ref $value && defined $value) # Just ID
    {
        $id = $value;
    }
    elsif ($value->{value} && ref $value->{value} eq 'GADS::Record')
    {
        $record = $value->{value};
        $id = $record->current_id;
    }
    elsif (my $r = $value->{record})
    {
        $record = GADS::Record->new(
            layout               => $self->column->layout_parent,
            record               => $r->{current}->{record_single},
            linked_id            => $r->{current}->{linked_id},
            parent_id            => $r->{current}->{parent_id},
            columns_retrieved_do => $self->column->curval_fields_retrieve(all_fields => $self->column->retrieve_all_columns),
        );
        $id = $r->{current_id};
    }
    else {
        panic "Unexpected value: $value";
    }

    ($record, $id);
}

1;
