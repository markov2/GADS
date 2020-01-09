#!/usr/bin/perl -CS

=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

use FindBin;
use lib "$FindBin::Bin/../lib";

use Dancer2;
use Dancer2::Plugin::DBIC;
use Path::Tiny;
use GADS::DB;
use Linkspace::Layout;
use GADS::Column::Calc;
use GADS::Column::Curval;
use GADS::Column::Date;
use GADS::Column::Daterange;
use GADS::Column::Enum;
use GADS::Column::File;
use GADS::Column::Intgr;
use GADS::Column::Person;
use GADS::Column::Rag;
use GADS::Column::String;
use GADS::Column::Tree;
use GADS::Config;
use GADS::Instances;
use GADS::Graph;
use GADS::Graphs;
use GADS::Groups;
use GADS::MetricGroups;
use GADS::Schema;
use Getopt::Long;
use JSON qw();
use Log::Report syntax => 'LONG';
use String::CamelCase qw(camelize);
use Path::Tiny;

my ($site_id, $purge, $add, $report_only, $merge, $update_cached, $force, @ignore_fields);

GetOptions (
    'site-id=s'      => \$site_id,
    'purge'          => \$purge,
    'add'            => \$add,           # Add as new table to existing system
    'report-only'    => \$report_only,
    'merge'          => \$merge,         # Merge into existing table
    'update-cached'  => \$update_cached,
    'force'          => \$force,         # Force updates
    'ignore-field=s' => \@ignore_fields,
) or exit;

$site_id or report ERROR =>  "Please provide site ID with --site-id";

-d '_export'
    or report ERROR => "Export directory does not exist";

GADS::Config->instance(
    config => config,
);

schema->site_id($site_id);

my $encoder = JSON->new;

my $guard = schema->txn_scope_guard;

if ($purge && !$report_only)
{
    foreach my $instance (@{GADS::Instances->new(schema => schema, user => undef, user_permission_override => 1)->all})
    {
        $instance->purge;
    }

    GADS::Groups->new(schema => schema)->purge;
}

schema->resultset('Group')->count && !$add && !$report_only && !$merge
    and report ERROR => "Groups already exists. Use --purge to remove everything from this site before import or --add to add config";

-d '_export/groups'
    or report ERROR => "Groups directory does not exist";

my $group_mapping; # ID mapping
my $groups = GADS::Groups->new(schema => schema);
foreach my $g(dir('_export/groups'))
{
    my ($group) = grep { $_->name eq $g->{name} } @{$groups->all};

    if ($group)
    {
        report TRACE => __x"Existing: Group {name} already exists", name => $g->{name}
            if $report_only;
    }
    else {
        report NOTICE => __x"Creation: New group {name} to be created", name => $g->{name};
        $group = GADS::Group->new(
            name   => $g->{name},
            schema => schema,
        );
        $group->write;
    }

    $group_mapping->{$g->{id}} = $group->id;
}

my $user_mapping;
if (-d '_export/users')
{
    foreach my $user (dir("_export/users"))
    {
        $user->{groups} = [map $group_mapping->{$_}, @{$user->{groups}}];
        my $u = schema->resultset('User')->import_hash($user);
        $user_mapping->{$user->{id}} = $u->id;
    }
}

opendir my $root, '_export' or report FAULT => "Cannot open directory _export";

my $column_mapping;
my $metrics_mapping;
my $record_mapping;
my $enum_mapping = {};
my $values_to_import = {};
my @all_columns;
my @all_layouts;
my %ignore_fields = map { $_ => 1 } @ignore_fields;

foreach my $ins (readdir $root)
{
    next unless $ins =~ /^instance/;

    my $instance_info = load_json("_export/$ins/instance");

    my $existing = rset('Instance')->search({
        name => $instance_info->{name},
    });

    my $instance;
    if (my $count = $existing->count)
    {
        report ERROR => __x"More than one existing instance name {name}",
            name => $instance_info->{name} if $count > 1;
        $instance = $existing->next;
        report NOTICE => __x"Existing: Instance {name} already exists", name => $instance_info->{name}
            if $report_only && !$merge;
        report ERROR => __x"Instance {name} already exists", name => $instance_info->{name}
            unless $merge;
    }
    else {
        report ERROR => __x"Instance name {name} does not exist. Specify --add to create it.",
            name => $instance_info->{name} if $merge && !$add;
        report NOTICE => __x"Creation: Instance name {name} created", name => $instance_info->{name};
        $instance = rset('Instance')->create({
            name   => $instance_info->{name},
        });

    }

    my $layout = Linkspace::Layout->new(
       user                     => undef,
       user_permission_override => 1,
       schema                   => schema,
       config                   => GADS::Config->instance,
       instance_id              => $instance->id,
    );
    $layout->create_internal_columns;

    $_->{group_id} = $group_mapping->{$_->{group_id}}
        foreach @{$instance_info->{permissions}};
    $layout->import_hash($instance_info, report_only => $report_only);
    $layout->write unless $report_only;

    my $topic_mapping; # topic ID mapping
    if (-d "_export/$ins/topics")
    {
        foreach my $topic (dir("_export/$ins/topics"))
        {
            my $top;
            my $topic_hash = {
                name                  => $topic->{name},
                description           => $topic->{description},
                initial_state         => $topic->{initial_state},
                click_to_edit         => $topic->{click_to_edit},
                prevent_edit_topic_id => $topic->{prevent_edit_topic_id},
                instance_id           => $instance->id,
            };
            if ($report_only || $merge)
            {
                $top = rset('Topic')->search({
                    name        => $topic->{name},
                    instance_id => $instance->id,
                });
                report ERROR => __x"More than one topic named {name} already exists", name => $topic->{name}
                    if $top->count > 1;
                report TRACE => __x"Existing: Topic {name} already exists, will update", name => $topic->{name}
                    if $top->count && $report_only;
                report NOTICE => __x"Creation: Topic {name} to be created", name => $topic->{name}
                    if !$top->count && $report_only;
                if ($top = $top->next)
                {
                    $top->import_hash($topic_hash, report_only => $report_only);
                    $top->update unless $report_only;
                }
            }
            if (!$top)
            {
                $top = schema->resultset('Topic')->create($topic_hash);
            }

            $topic_mapping->{$topic->{id}} = $top->id;
        }
    }

    my %existing_columns = map { $_->id => $_ } $layout->all(exclude_internal => 1);


    my $highest_update; # The column with the highest ID that's been updated
    my @created;
    foreach my $col (dir("_export/$ins/layout"))
    {
        my $updated;
        my $column = $layout->column_by_name($col->{name});

        if ($column && $ignore_fields{$column->name})
        {
            $column_mapping->{$col->{id}} = $column->id;
            next;
        }

        if ($column)
        {
            report TRACE => __x"Update: Column {name} already exists, will update", name => $col->{name}
                if $report_only;
            report ERROR => __x"Column {name} already exists", name => $col->{name}
                unless $merge;
            report ERROR => __x"Existing column type does not match import for column name {name} in table {table}",
                name => $col->{name}, table => $layout->name
                    if $col->{type} ne $column->type;
            $highest_update = $col->{id} if !$highest_update || $col->{id} > $highest_update;
            $updated = 1;
        }

        if (!$column)
        {
            report NOTICE => __x"Creation: Column {name} to be created", name => $col->{name};
            push @created, $col;
        }

        my $class = "GADS::Column::".camelize($col->{type});
        $column ||= $class->new(
            type   => $col->{type},
            schema => schema,
            user   => undef,
            layout => $layout,
        );
        $column->import_hash($col, report_only => $report_only, force => $force);
        $column->topic_id($topic_mapping->{$col->{topic_id}}) if $col->{topic_id};
        # Don't add to the DBIx schema yet, as we may not have all the
        # information needed (e.g. related field IDs)
        $column->write(override => 1, no_db_add => 1, no_cache_update => 1, update_dependents => 0, enum_mapping => $enum_mapping);
        $column->import_after_write($col, report_only => $updated && $report_only, force => $force, enum_mapping => $enum_mapping);

        my $perms_to_set = {};
        foreach my $old_id (keys %{$col->{permissions}})
        {
            my $new_id = $group_mapping->{$old_id};
            $perms_to_set->{$new_id} = $col->{permissions}->{$old_id};
        }
        $column->set_permissions($perms_to_set, report_only => $report_only);

        $column_mapping->{$col->{id}} = $column->id;

        push @all_columns, {
            column  => $column,
            values  => $col,
            updated => $updated,
        };

        delete $existing_columns{$column->id};
    }

    # Check for fields that look like new columns (with a different name) but
    # have an ID older than existing columns. These are probably fields that
    # have had their name changed
    foreach my $create (@created)
    {
        report NOTICE => __x"Suspected name updated: column {name} was created but its "
            ."ID is less than those already existing. Could it be an updated name?", name => $create->{name}
            if $highest_update && $create->{id} < $highest_update;
    }

    if ($merge)
    {
        foreach my $col (values %existing_columns)
        {
            unless ($ignore_fields{$col->name})
            {
                report NOTICE => __x"Deletion: Column {name} no longer exist", name => $col->name;
                $col->delete
                    unless $report_only;
            }
        }
    }

    foreach my $mg (dir("_export/$ins/metrics"))
    {
        my $existing = schema->resultset('MetricGroup')->search({
            name => $mg->{name},
        })->next;
        my $metric_group;
        if ($existing)
        {
            $metric_group = GADS::MetricGroup->new(
                id          => $existing->id,
                instance_id => $layout->instance_id,
                schema      => schema,
            );
        }
        else {
            $metric_group = GADS::MetricGroup->new(
                name        => $mg->{name},
                instance_id => $layout->instance_id,
                schema      => schema,
            );
            $metric_group->write;
        }
        $metric_group->import_hash($mg);
        $metrics_mapping->{$mg->{id}} = $metric_group->id;
    }

    $layout->clear;

    # The layout in a column is a weakref, so it will have been destroyed by
    # the time we try and use it later in the script. Therefore, keep a
    # reference to it.
    push @all_layouts, {
        values => $instance_info,
        layout => $layout,
        # Can't do graphs now as they may refer to other tables that haven't
        # been imported yet
        graphs => "_export/$ins/graphs",
    };

    my $records_dir = "_export/$ins/records";
    if (-d $records_dir)
    {
        foreach my $record (dir($records_dir))
        {
            my $c = schema->resultset('Current')->import_hash($record,
                instance         => $instance,
                user_mapping     => $user_mapping,
                values_to_import => $values_to_import,
                column_mapping   => $column_mapping,
            );
            $record_mapping->{$record->{id}} = $c->id;
        }
    }
    # XXX Then do record_id entries in records
}

foreach my $l (@all_layouts)
{
    my $layout = $l->{layout};
    $layout->import_after_all($l->{values}, mapping => $column_mapping, report_only => $report_only);
    $layout->write;
    $layout->clear;

    foreach my $g (dir($l->{graphs}))
    {
        # Convert to new column IDs
        $g->{x_axis} = $column_mapping->{$g->{x_axis}}
            if $g->{x_axis};
        $g->{x_axis_link} = $column_mapping->{$g->{x_axis_link}}
            if $g->{x_axis_link};
        $g->{y_axis} = $column_mapping->{$g->{y_axis}};
        $g->{group_by} = $column_mapping->{$g->{group_by}}
            if $g->{group_by};
        $g->{metric_group_id} = $metrics_mapping->{$g->{metric_group_id}}
            if $g->{metric_group_id};

        # And users and groups where applicable
        $g->{user_id} = $user_mapping->{$g->{user_id}}
            if $user_mapping && $g->{user_id};
        $g->{group_id} = $group_mapping->{$g->{group_id}}
            if $group_mapping && $g->{group_id};

        my $graph;
        if ($merge || $report_only)
        {
            my $graph_rs = rset('Graph')->search({
                title => $g->{title},
            });
            report ERROR => "More than one existing graph titled {title}", title => $g->{title}
                if $graph_rs->count > 1;
            if ($graph_rs->count)
            {
                $graph = GADS::Graph->new(
                    id     => $graph_rs->next->id,
                    layout => $layout,
                    schema => schema,
                );
            }
            else {
                report NOTICE => __x"Graph to be created: {graph}", graph => $g->{title};
            }
        }
        $graph ||= GADS::Graph->new(
            layout => $layout,
            schema => schema,
        );
        $graph->import_hash($g, report_only => $report_only);
        $graph->write unless $report_only;
    }

}

foreach (@all_columns)
{
    my $col = $_->{column};

    next if $ignore_fields{$col->name};

    foreach my $val (@{$values_to_import->{$col->id}})
    {
        $val->{value} = $val->{value} && $record_mapping->{$val->{value}}
            if $col->type eq 'curval';
        $val->{value} = $val->{value} && $enum_mapping->{$val->{value}}
            if $col->type eq 'enum' || $col->type eq 'tree';
        $val->{value} = $val->{value} && $user_mapping->{$val->{value}}
            if $col->type eq 'person';
        $col->import_value($val);
    }

    report TRACE => __x"Final update of column {name}", name => $col->name;
    $col->import_after_all($_->{values}, mapping => $column_mapping, report_only => $report_only && $_->{updated}, force => $force);
    # Now add to the DBIx schema
    $col->write(no_cache_update => 1, add_db => 1, update_dependents => 1, report_only => $report_only);
}

if (!$report_only && $update_cached)
{
    GADS::DB->setup(schema);
    $_->{column}->can('update_cached') && $_->{column}->update_cached(no_alerts => 1)
        foreach @all_columns;
}

exit if $report_only;
$guard->commit;

sub dir
{   my $name = shift;
    opendir my $dir, $name or report FAULT => "Cannot open directory $name";
    map { load_json("$name/$_") } grep { $_ ne '.' && $_ ne '..' } sort readdir $dir;
}

sub load_json
{   my $file = shift;
    my $json = path($file)->slurp_utf8;
    $encoder->decode($json);
}
