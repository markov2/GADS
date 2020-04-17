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

use Dancer2;
use Dancer2::Plugin::DBIC;
use Path::Tiny;
use Getopt::Long;
use JSON qw();
use Log::Report syntax => 'LONG';
use String::CamelCase qw(camelize);
use Path::Tiny;

use Linkspace;
use Linkspace::Util qw(index_by_id);

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

Linkspace->start(site => $site_id);
my $site = $::session->site($site_id);

my $encoder = JSON->new;

my $guard = $::db->begin_work;

if ($purge && !$report_only)
{   $document->purge;   # remove all sheets and groups
}

if($add || $report_only || $merge)
{   my $groups = $site->groups;
    report ERROR => "Groups already exists. Use --purge to remove everything from this site before import or --add to add config"
        if @$groups;

-d '_export/groups'
    or report ERROR => "Groups directory does not exist";

my %group_ext2int; # ID mapping

foreach my $g (dir('_export/groups'))
{   my $group_name = $g->{name};
    my $orig_id = delete $g->{id};
    my $groups  = $site->groups;

    my $group;
    if($group  = $groups->group_by_name($group_name))
    {   report TRACE => __x"Existing: Group {name} already exists",
            name => $group_name
            if $report_only;
    }
    else
    {   report NOTICE => __x"Creation: New group {name} to be created",
            name => $group_name;
        $group = $groups->group_create($g);
    }

    $group_ext2int{$g->{id}} = $group->id;
}

my %user_ext2int;
if (-d '_export/users')
{   my $users = $site->users;
    foreach my $ui (dir "_export/users")
    {   $ui->{group_ids} = [ map $group_ext2int{$_}, @{delete $ui->{groups}} ];
        $ui->{pwchanged} = iso2datetime($ui->{pwchanged});
        $ui->{deleted}   = iso2datetime($ui->{deleted});
        $ui->{lastlogin} = iso2datetime($ui->{lastlogin});
        $ui->{created}   = iso2datetime($ui->{created});
 
        my $user;
        if($user = $users->user_by_name($ui->{email});
        {   $users->user_update($user, $ui);
        }
        else
        {   $user = $users->user_create($ui);
        }
        $user_ext2int{$ui->{id}} = $user->id;
    }
}

opendir my $root, '_export'
    or report FAULT => "Cannot open directory _export";

my (%column_ext2int, %metrics_ext2int, %record_ext2int, %enum_ext2int);
my %values_to_import;
my (@columns_todo, @all_layouts);

my %ignore_fields = map +($_ => 1), @ignore_fields;

foreach my $ins (readdir $root)
{   $ins =~ /^instance/ or next;
    my $sheet_info = load_json "_export/$ins/instance";
    my $sheet_name = delete $sheet_info->{name};

    $_->{group_id} = $group_ext2int{$_->{group_id}}
        for @{$sheet_info->{permissions}};

    my $sheet;
    if($sheet = $site->sheet(name => $sheet_name))
    {
        report NOTICE => __x"Existing: Sheet {name} already exists", name => $sheet_name
            if $report_only && !$merge;

        report ERROR => __x"Sheet {name} already exists; merge?", name => $sheet_name
            if !$merge;


        my $sheet = $site->document->sheet_update($sheet, $sheet_info);
    }
    else
    {   report ERROR => __x"Instance name {name} does not exist. Specify --add to create it.",
            name => $sheet_name
            if $merge && !$add;

        report NOTICE => __x"Creation: Instance name {name} created",
            name => $sheet_name;

        $sheet = $site->document->sheet_create($sheet_info,
           report_only => $report_only,
        );
    }

    my %topic_ext2int;
    if (-d "_export/$ins/topics")
    {
        foreach my $ext (dir "_export/$ins/topics")
        {   my $topic_name = $ext->{name};
            my %int = (
                name                  => $name,
                description           => $ext->{description},
                initial_state         => $ext->{initial_state},
                click_to_edit         => $ext->{click_to_edit},
                prevent_edit_topic_id => $ext->{prevent_edit_topic_id},
            );

            my $topic;
            if($report_only || $merge)
            {   my $found = $sheet->topics_with_name($name);

                report ERROR => __x"More than one topic named {name} already exists",
                    name => $topic_name
                    if @$found > 1;

                report TRACE => __x"Existing: Topic {name} already exists, will update",
                    name => $topic_name
                    if @$found && $report_only;

                report NOTICE => __x"Creation: Topic {name} to be created",
                    name => $topic_name
                    if !@$found && $report_only;

                $topic = $found->[0];

                $sheet->topic_update($top, \%int, report_only => $report_only);
                    unless $report_only;
            }

            $topic ||= $sheet->topic_create(\%int);
            $topic_ext2int{$ata->{id}} = $topic->id;
        }
    }

    my $highest_update;   # The column with the highest ID that's been updated
    my %remove_columns;
    my @created;
    foreach my $data (dir "_export/$ins/layout")
    {   my $name   = $data->{name};
        my $column = $layout->column_by_name($name);

        if($column)
        {   if($ignore_fields{$name})
            {   $column_ext2int{$data->{id}} = $column->id;
                next;
            }

            report TRACE => __x"Update: Column {name} already exists, will update",
                name => $name
                if $report_only;

            report ERROR => __x"Column {name} already exists", name => $name
                unless $merge;

            report ERROR => __x"Existing column type does not match import for column name {name} on sheet {sheet}",
                name => $name, sheet => $sheet->name
                if $data->{type} ne $column->type;

            $highest_update = $column->id
                if !$highest_update || $column->id > $highest_update;

            delete $remove_columns{$column->id};
        }
        else
        {   report NOTICE => __x"Creation: Column {name} to be created", name => $name;
            push @created, $data;
        }

        $data->{topic_id} = $topic_ext2int{$data->{topic_id}}
            if $data->{topic_id};

        my %perms_to_set;
        foreach my $ext_group_id (keys %{delete $data->{permissions}})
        {   my $int_group_id = $group_ext2int{$ext_group_id};
            $perms_to_set{$int_group_id} = $data->{permissions}{$ext_group_id};
        }
        $data->{permissions} = \%perms_to_set;

        my $updated = ! $column;
        $column ||= $layout->column_create({    # very minimal create now
             name => $name,
             type => $data->{type},
        });

        push @columns_todo, {
            column  => $column,
            data    => $data,
            updated => $updated,
        };

        $column_ext2int{$data->{id}} = $column->id;
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
    {   foreach my $column (values %remove_columns)
        {   next if $ignore_fields{$column->name};
            report NOTICE => __x"Deletion: Column {name} no longer exist",
                name => $column->name;
            $layout->column_delete($column) unless $report_only;
        }
    }

    foreach my $mg (dir "_export/$ins/metrics")
    {   my $mg_name = $mg->{name};
        my $metric_group_id;
        if(my $metric_group = $sheet->metric_group_by_name($mg_name))
        {   $metric_group->metric_group_update($mg);
            $$metrics_ext2int{$mg->{id}} = $metric_group->id;
        }
        else
        {   my $mg = $sheet->metric_group_create($msg);
            $$metrics_ext2int{$mg->{id}} = $mg->id;
        }
    }

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
            my $c = $::db->resultset('Current')->import_hash($record,
                instance         => $instance,
                user_ext2int     => \%user_ext2int,
                values_to_import => \%values_to_import,
                column_ext2int   => \%column_ext2int,
            );
            $record_ext2int{$record->{id}} = $c->id;
        }
    }
    # XXX Then do record_id entries in records
}

foreach my $l (@all_layouts)
{
    my $layout = $l->{layout};
    if(my $sort_id = $l->{values}->{sort_layout_id})
    {   my $new_id = $column_ext2int{$sort_id};
        my $old_id = $sheet->sort_layout_id;

        notice __x"Update: sort_layout_id from {old} to {new} for {name}",
            old => $old_id, new => $new_id, name => $self->name
                if $report && ($old_id // 0) != ($new_id // 0);

        $sheet->sheet_update(sort_layout_id => $new_id );
    }

    foreach my $g (dir($l->{graphs}))
    {
        $g->{$_} = $column_ext2int{$g->{$_}}
            for grep defined $g->{$_}, qw/x_axis x_axis_link y_axis group_by/;

        $g->{metric_group_id} = $$metrics_ext2int{$g->{metric_group_id}}
            if $g->{metric_group_id};

        # And users and groups where applicable
        $g->{user_id} = $user_ext2int{$g->{user_id}}
            if keys %user_ext2int && $g->{user_id};

        $g->{group_id} = $group_ext2int{$g->{group_id}}
            if keys %group_ext2int && $g->{group_id};

        my $graph;
        if ($merge || $report_only)
        {   my $title = $g->{title};

            if(my $graph = $sheet->graphs_with_title($title))
            {   $graph->show_changes($g) if $report;
                $sheet->graph_update($graph, $g);
            }
            else
            {   report NOTICE => __x"Graph to be created: {graph}", graph => $title;
                $graph = $sheet->graph_create($g);
            }
        }
    }
}

foreach my $todo (@columns_todo)
{   my $column    = $todo->{column};
    my $data      = $todo->{data};
    my $is_update = $todo->{is_update};

    next if $ignore_fields{$column->name};

    report TRACE => __x"Final update of column {name}", name => $column->name;
    if(my $rel_id = delete $data->{related_field_id})
    {   $data->{related_field} = $column_ext2int{$rel_id};
    }

    if(my $curval_ids = $data->{curval_field_ids}})
    {   $data->{curval_field_ids} = map $column_ext2int{$_}, @$curval_ids;
    }

    if(my $filter = $data->{filter})
    {   $data->{filter} = Linkspace::Filter->from_json(sheet => $any_sheet)
            ->renumber_columns(\%column_ext2int);
    }

    $column->column_update($data,
        report => $report_only && $todo->{updated},
        force  => $force
        no_cache_update   => 1,
        update_dependents => 1,
    );

    foreach my $val (@{$values_to_import{$column->id}})
    {   my $type = $col->type;
        if(my $v = $val->{value})
        {   $val->{value}
               = $type eq 'curval' ? $record_ext2int{$v}
               : $type eq 'enum'   ? $enum_ext2int{$v}
               : $type eq 'tree'   ? $enum_ext2int{$v}
               : $type eq 'person' ? $user_ext2int{$v}
               :                     $v;
        }

        $column->import_value($val);
    }
}

if(!$report_only && $update_cached)
{   $_->can('update_cached') && $_->update_cached(no_alerts => 1)
        for map $_->{column}, @columns_todo;
}

if($report_only) { $guard->rollback }
else             { $guard->commit }

#### Helpers

sub dir
{   my $name = shift;
    opendir my $dir, $name or report FAULT => "Cannot open directory $name";
    map load_json("$name/$_"),
        grep { $_ ne '.' && $_ ne '..' }
            sort readdir $dir;
}

sub load_json
{   my $file = shift;
    my $json = path($file)->slurp_utf8;
    $encoder->decode($json);
}
