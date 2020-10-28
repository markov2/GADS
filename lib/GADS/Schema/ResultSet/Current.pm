## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Schema::ResultSet::Current;

use strict;
use warnings;

use parent 'DBIx::Class::ResultSet';

use Log::Report 'linkspace';

__PACKAGE__->load_components(qw/
    Helper::ResultSet::DateMethods1
    +GADS::Helper::Concat
    Helper::ResultSet::CorrelateRelationship
    Helper::ResultSet::Random
    /
);

sub import_hash
{   my ($self, $record, %params) = @_;

    my $schema = $self->result_source->schema;

    my $current = $self->create({
        instance_id => $params{instance}->id,
        serial      => $record->{serial},
        deleted     => $record->{deleted},
        deletedby   => $record->{deletedby},
    });

    foreach my $r (@{$record->{records}})
    {
        error __"Import of record_id value not yet support"
            if $r->{record_id};
        my $rec = $schema->resultset('Record')->import_hash($r, current => $current, %params);
    }

    return $current;
}

1;
