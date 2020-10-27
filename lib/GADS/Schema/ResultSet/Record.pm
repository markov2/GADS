## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Schema::ResultSet::Record;

use strict;
use warnings;

use Linkspace::Util  qw(iso2datetime);

use parent 'DBIx::Class::ResultSet';

sub import_hash
{   my ($self, $rec, %params) = @_;

    my $user_mapping     = $params{user_mapping};
    my $column_mapping   = $params{column_mapping};
    my $values_to_import = $params{values_to_import};

    my $record = $self->create({
        current_id => $params{current}->id,
        created    => iso2datetime($rec->{created}),
        createdby  => $user_mapping->{$rec->{createdby}},
        approvedby => $rec->{approved_by} && $user_mapping->{$rec->{approvedby}},
        approval   => $rec->{approval},
    });

    foreach my $value (@{$rec->{values}})
    {
        my $col_id = delete $value->{layout_id};
        $col_id = $column_mapping->{$col_id};
        $values_to_import->{$col_id} ||= [];
        $value->{record_id} = $record->id;
        push @{$values_to_import->{$col_id}}, $value;
    }

    return $record;
}

1;
