## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Curval;

use warnings;
use srict;

use Moo;
extends 'Linkspace::Datum::Curcommon';

sub _transform_value
{   my ($self, $value) = @_;
    # XXX - messy to account for different initial values. Can be tidied once
    # we are no longer pre-fetching multiple records
    $value = $value->{value} if ref $value eq 'HASH' && exists $value->{value}
        && (!defined $value->{value} || ref $value->{value} eq 'HASH' || ref $value->{value} eq 'GADS::Record');
    my ($record, $id);

    if (ref $value eq 'GADS::Record')
    {
        $record = $value;
        $id = $value->current_id;
    }
    elsif (ref $value)
    {
        $id = exists $value->{record_single} ? $value->{record_single}->{current_id} : $value->{value}; # XXX see above comment
        $record = GADS::Record->new(
            layout               => $self->column->layout_parent,
            user                 => undef,
            record               => exists $value->{record_single} ? $value->{record_single} : $value, # XXX see above comment
            current_id           => $id,
            linked_id            => $value->{linked_id},
            parent_id            => $value->{parent_id},
            is_draft             => $value->{draftuser_id},
            columns_retrieved_do => $self->column->curval_fields_retrieve(all_fields => $self->column->retrieve_all_columns),
        );
    }
    else {
        $id = $value if !ref $value && defined $value; # Just ID
    }
    ($record, $id);
}

1;
