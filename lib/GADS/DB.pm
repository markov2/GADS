## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::DB;

use strict;
use warnings;

use String::CamelCase qw(camelize);

sub setup
{   my ($class, $schema) = @_;

    my $layout_rs = $schema->resultset('Layout');
    my @cols = $layout_rs->search({ internal => 0 })->all;

    foreach my $col (@cols)
    {   $class->add_column($schema, $col);
    }

    my $rec_class = $schema->class('Record');
    $rec_class->might_have(
        record_previous => 'Record',
        sub {
			my ($me, $other) = ($_[0]->{self_alias}, $_[0]->{foreign_alias});

            return {
                "$other.current_id"  => { -ident => "$me.current_id" },
                "$other.id"          => { '<' => \"$me.id" },
            };
        }
    );

    GADS::Schema->unregister_source('Record');
    GADS::Schema->register_class(Record => $rec_class);

    $schema->unregister_source('Record');
    $schema->register_class(Record => $rec_class);

}

sub add_column
{   my $self = shift;
    $self->_add_column(@_);
    $self->_add_column(@_, 1);
}

sub _add_column
{   my ($class, $schema, $col, $alt) = @_;

    my $colname = "field".$col->id;
    # We add each column twice, with a standard join and with an alternative
    # join. The alternative join allows correlated sub-queries to be used, with
    # the inner sub-query referencing a value from the main query
    $colname .= "_alternative" if $alt;

    # Temporary hack
    # very inefficient and needs to go away when the rel options show up
    my $rec_class = $schema->class('Record');
    if ($col->type eq 'autocur')
    {
        # Capture now before any weakrefs go out of scope
        my $related_field_id = $col->related_field->id;

        my $subquery = $schema->resultset('Current')->search({
            'record_later.id' => undef,
        },{
            join => {
                record_single => 'record_later'
            },
        })->get_column('record_single.id')->as_query;

        $rec_class->has_many(
            $colname => 'Curval',
            sub {
                my $args = shift;
                my $other = $args->{foreign_alias};

                return {
                    "$other.value"     => { -ident => "$args->{self_alias}.current_id" },
                    "$other.layout_id" => $related_field_id,
                    "$other.record_id" => { -in => $subquery },
                };
            }
        );
    }
    else {
        my $coltype = $col->type eq "tree" ? 'enum'
                    : $col->type eq "calc" ? 'calcval'
                    : $col->type eq "rag"  ? 'ragval'
                    : $col->type;

        $rec_class->has_many(
            $colname => camelize($coltype),
            sub {
                my $args = shift;
                my $other = $args->{foreign_alias};

                return {
                    "$other.record_id" => { -ident => "$args->{self_alias}.id" },
                    "$other.layout_id" => $col->id,
                };
            }
        );
    }

    GADS::Schema->unregister_source('Record');
    GADS::Schema->register_class(Record => $rec_class);

    $schema->unregister_source('Record');
    $schema->register_class(Record => $rec_class);
}

sub update
{   my ($class, $schema) = @_;

    # Find out what latest field ID is
    my $max = $schema->resultset('Layout')->search({ internal => 0 })->get_column('id')->max
        or return; # No fields

    # Does this exist as an accessor?
    my $rec_rsource = $schema->resultset('Record')->result_source;
    unless ($rec_rsource->has_relationship("field$max"))
    {
        # No. Need to go back until we find the one that exists
        my $id = $max;
        $id-- while !$rec_rsource->has_relationship("field$id");
        $id++; # Start at one the doesn't exist
        for ($id..$max) {
            # Add them/it
            my $col = $schema->resultset('Layout')->find($_);
            $class->add_column($schema, $col)
                if $col; # May have since been deleted
            $class->add_column($schema, $col, 1)
                if $col; # May have since been deleted
        }
    }
}

1;

