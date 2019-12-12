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

package GADS::Layout;

use Log::Report 'linkspace';

use GADS::Column;
use GADS::Column::Autocur;
use GADS::Column::Calc;
use GADS::Column::Createdby;
use GADS::Column::Createddate;
use GADS::Column::Curval;
use GADS::Column::Date;
use GADS::Column::Daterange;
use GADS::Column::Deletedby;
use GADS::Column::Enum;
use GADS::Column::File;
use GADS::Column::Id;
use GADS::Column::Intgr;
use GADS::Column::Person;
use GADS::Column::Rag;
use GADS::Column::Serial;
use GADS::Column::String;
use GADS::Column::Tree;
use GADS::Instances;
use GADS::Graphs;
use GADS::MetricGroups;
use GADS::Views;
use String::CamelCase qw(camelize);

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

has schema => (
    is       => 'rw',
    required => 1,
);

has user => (
    is       => 'rw',
    required => 1,
);

has config => (
    is       => 'ro',
    required => 1,
);

has instance_id => (
    is  => 'rwp',
    isa => Int,
);

has _rset => (
    is      => 'lazy',
    clearer => 1,
);

has name => (
    is      => 'rw',
    isa     => Str,
);

has name_short => (
    is      => 'rw',
    isa     => Maybe[Str],
);

has identifier => (
    is      => 'lazy',
);

has homepage_text => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_rset->homepage_text },
    clearer => 1,
);

has homepage_text2 => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_rset->homepage_text2 },
    clearer => 1,
);

has forget_history => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => sub { $_[0]->_rset->forget_history },
    clearer => 1,
);

has forward_record_after_create => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => sub { $_[0]->_rset->forward_record_after_create },
    clearer => 1,
);

has no_hide_blank => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => sub { $_[0]->_rset->no_hide_blank },
    clearer => 1,
);

has no_overnight_update => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => sub { $_[0]->_rset->no_overnight_update },
    clearer => 1,
);

has sort_layout_id => (
    is      => 'rw',
    isa     => Maybe[Int],
    lazy    => 1,
    clearer => 1,
    builder => sub { $_[0]->_rset->sort_layout_id },
);

has default_view_limit_extra => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub { $_[0]->_rset->default_view_limit_extra },
);

has default_view_limit_extra_id => (
    is      => 'ro',
    isa     => Maybe[Int],
    lazy    => 1,
    clearer => 1,
    builder => sub { $_[0]->_rset->default_view_limit_extra_id },
);

has api_index_layout => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->column($self->_rset->api_index_layout_id);
    },
    clearer => 1,
);

has api_index_layout_id => (
    is      => 'ro',
    isa     => Maybe[Int],
    lazy    => 1,
    builder => sub { $_[0]->_rset->api_index_layout_id },
    clearer => 1,
);

has sort_type => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    builder => sub { $_[0]->_rset->sort_type },
);

# Reference to the relevant record using this layout if applicable. Used for
# filtered curvals
has record => (
    is       => 'rw',
    weak_ref => 1,
);

has columns => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    builder => '_build_columns',
);

has _columns_namehash => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

has _columns_name_shorthash => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

sub _build__user_permissions_columns
{   my $self = shift;
    $self->user or return {};

    my $user_id  = $self->user->id;

    +{
        $user_id => $self->_get_user_permissions($user_id),
    };
}

sub _get_user_permissions
{   my ($self, $user_id) = @_;
    my $user_perms = $site->get_record(User => {
        'me.id'              => $user_id,
    },
    {
        prefetch => {
            user_groups => {
                group => { layout_groups => 'layout' },
            }
        },
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    });

    my $return;
    if ($user_perms) # Might not be any at all
    {
        foreach my $group (@{$user_perms->{user_groups}}) # For each group the user has
        {
            foreach my $layout_group (@{$group->{group}->{layout_groups}}) # For each column in that group
            {
                # Push the actual permission onto an array
                $return->{$layout_group->{layout_id}}->{$layout_group->{permission}} = 1;
            }
        }
    }
    return $return;
}

has _user_permissions_overall => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

sub _build__user_permissions_overall
{   my $self = shift;
    my $user_id = $::session->user->id;
    my $overall = {};

    # First all the column permissions
    if(my $h = $user->sheet_permissions($self))
    {
        $overall->{$_} = 1 for keys %$h;
    }
    else {
        my $perms = $self->_user_permissions_columns->{$user_id};
        foreach my $col_id (@{$self->all_ids})
        {
            $overall->{$_} = 1
                foreach keys %{$perms->{$col_id}};
        }
    }

    # Then the table permissions
    my $perms = $user->sheet_permissions($self);
    $overall->{$_} = 1
        foreach keys %$perms;

    if($perms->{superadmin})
    {   $overall->{layout} = 1;
        $overall->{view_create} = 1;
    }

    $overall;
}

sub current_user_can_column
{   my ($self, $column_id, $permission) = @_;
    my $user = $self->user
        or return;
    my $user_id  = $user->id;
    return $self->user_can_column($user_id, $column_id, $permission);
}

sub user_can_column
{   my ($self, $user_id, $column_id, $permission) = @_;

    my $user_cache = $self->_user_permissions_columns->{$user_id};

    if (!$user_cache)
    {
        my $user_permissions = $self->_user_permissions_columns;
        $user_cache = $user_permissions->{$user_id} = $self->_get_user_permissions($user_id);
    }

    return $user_cache->{$column_id}->{$permission};
}

has _group_permissions => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build__group_permissions
{   my $self = shift;
    [
        $self->schema->resultset('InstanceGroup')->search({
            instance_id => $self->instance_id,
        })->all
    ];
}

has _group_permissions_hash => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

sub _build__group_permissions_hash
{   my $self = shift;
    my $return = {};
    foreach (@{$self->_group_permissions})
    {
        $return->{$_->group_id}->{$_->permission} = 1;
    }
    $return;
}

sub group_has
{   my ($self, $group_id, $permission) = @_;
    my $h = $self->_group_permissions_hash->{$group_id};
    $h && $h->{$permission};
}

has user_permission_override => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

has user_permission_override_search => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

has columns_index => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $self = shift;
        +{ map +($_->{id} => $_) @{$self->columns} };
    },
);

has set_groups => (
    is        => 'rw',
    isa       => ArrayRef,
    predicate => 1,
);

sub write
{   my $self = shift;

    my $rset;
    if (!$self->instance_id)
    {   my $sheet = Linkspace::Sheet->create;
        $self->_set_instance_id($sheet->id);
    }
    else {
        $rset = $self->_rset;
    }

    $rset->update({
        name           => $self->name,
        name_short     => $self->name_short,
        homepage_text  => $self->homepage_text,
        homepage_text2 => $self->homepage_text2,
        sort_type      => $self->sort_type,
        sort_layout_id => $self->sort_layout_id,
    });

    # Now set any groups if needed
    if ($self->has_set_groups)
    {
        my @create;
        my $delete = {};

        my %valid = (
            delete           => 1,
            purge            => 1,
            download         => 1,
            layout           => 1,
            message          => 1,
            view_create      => 1,
            view_group       => 1,
            create_child     => 1,
            bulk_update      => 1,
            link             => 1,
            view_limit_extra => 1,
        );

        my $existing = $self->_group_permissions_hash;

        # Parse the form submimssion. Take the existing permissions: if exists, do
        # nothing, otherwise create
        foreach my $perm (@{$self->set_groups})
        {
            $perm =~ /^([0-9]+)\_(.*)/;
            my ($group_id, $permission) = ($1, $2);
            $group_id && $valid{$permission}
                or panic "Invalid permission $perm";
            # If it exists, delete from hash so we know what to delete
            delete $existing->{$group_id}->{$permission}
                or push @create, { instance_id => $self->instance_id, group_id => $group_id, permission => $permission };

        }
        # Create anything we need
        $self->schema->resultset('InstanceGroup')->populate(\@create);

        # Delete anything left - not in submission so therefore removed
        my @delete;
        foreach my $group_id (keys %$existing)
        {
            foreach my $permission (keys %{$existing->{$group_id}})
            {
                push @delete, {
                    instance_id => $self->instance_id,
                    group_id    => $group_id,
                    permission  => $permission,
                };
            }
        }
        $self->schema->resultset('InstanceGroup')->search([@delete])->delete
            if @delete;
    }
    $self->clear; # Rebuild all permissions etc
    $self; # Return self for chaining
}

### Each empty sheet gets them
my @internal_columns = (
    {
        name        => 'ID',
        type        => 'id',
        name_short  => '_id',
        isunique    => 1,
    },
    {
        name        => 'Last edited time',
        type        => 'createddate',
        name_short  => '_version_datetime',
        isunique    => 0,
    },
    {
        name        => 'Last edited by',
        type        => 'createdby',
        name_short  => '_version_user',
        isunique    => 0,
    },
    {
        name        => 'Created by',
        type        => 'createdby',
        name_short  => '_created_user',
        isunique    => 0,
    },
    {
        name        => 'Deleted by',
        type        => 'deletedby',
        name_short  => '_deleted_by',
        isunique    => 0,
    },
    {
        name        => 'Created time',
        type        => 'createddate',
        name_short  => '_created',
        isunique    => 0,
    },
    {
        name        => 'Serial',
        type        => 'serial',
        name_short  => '_serial',
        isunique    => 1,
    },
);

sub create($)
{   my $sheet = shift;
    my $sheet_id = $sheet->id;

    foreach my $col (@internal_columns)
    {
        # Already exists?
        next if $site->get_record(Layout => {
            instance_id => $sheet_id
            name_short  => $col->{name_short},
        });

        $site->create(Layout => {
            name        => $col->{name},
            type        => $col->{type},
            name_short  => $col->{name_short},
            isunique    => $col->{isunique},
            can_child   => 0,
            internal    => 1,
            instance_id => $sheet_id
        });
    }
}

=head2 my @cols = $class->load_columns;
Initially load all column information for a certain site.
=cut

sub load_columns($)
{   my ($class, $site) = @_;

    [ $::linkspace->db->search(Layout => {
        'instance.site_id' => $site->id,
    },{
        select   => 'me.*',
        join     => 'instance',
        prefetch => [ qw/calcs rags link_parent display_fields/ ],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    })->all ];
}

# Instantiate new class. This builds a list of all
# columns, so that it's cached for any later function
sub _build_columns
{   my $self = shift;

    my @return;
    foreach my $col (@{$self->cols_db})
    {
        my $class = "GADS::Column::".camelize $col->{type};
        my $column = $class->new(
            set_values               => $col,
            internal                 => $col->{internal},
            instance_id              => $col->{instance_id},
        );
        push @return, $column;
    }

    \@return;
}

# Array with all the IDs of the columns of this layout. This is used to save
# having to fully build all columns if only the IDs are needed
has all_ids => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build_all_ids
{   my $self = shift;
    [ map $_->{id}, grep { $_->{instance_id} == $self->instance_id } @{$self->cols_db} ]
}

has has_globe => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_has_globe
{   my $self = shift;
    !! grep { $_->return_type eq "globe" } $self->all;
}

has has_children => (
    is      => 'lazy',
    isa     => Bool,
    clearer => 1,
);

sub _build_has_children
{   my $self = shift;
    !! grep { $_->can_child } $self->all;
}

has has_topics => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_has_topics
{   my $self = shift;
    !! $self->schema->resultset('Topic')->search({ instance_id => $self->instance_id })->next;
}

has col_ids_for_cache_update => (
    is  => 'lazy',
    isa => ArrayRef,
);

# All the column IDs needed to update all cached fields. This is all the
# calculated/rag fields, plus any fields that they depend on
sub _build_col_ids_for_cache_update
{   my $self = shift;

    # First all the "parent" fields (the calc/rag fields)
    my %cols = map { $_ => 1 } $self->schema->resultset('LayoutDepend')->search({
        instance_id => $self->instance_id,
    },{
        join     => 'layout',
        group_by => 'me.layout_id',
    })->get_column('layout_id')->all;

    # Then all the fields they depend on
    $cols{$_} = 1 foreach $self->schema->resultset('LayoutDepend')->search({
        instance_id => $self->instance_id,
    },{
        join     => 'depend_on',
        group_by => 'me.depends_on',
    })->get_column('depends_on')->all;

    # Finally ensure all the calc/rag fields are included. If they only use an
    # internal column, then they won't have been part of the layout_depend
    # table
    $cols{$_->id} = 1 foreach $self->all(has_cache => 1);

    return [ keys %cols ];
}

sub all_with_internal
{   my $self = shift;
    $self->all(@_, include_internal => 1);
}

sub columns_for_filter
{   my ($self, %options) = @_;
    my @columns;
    my %restriction = (include_internal => 1);
    $restriction{user_can_read} = 1 unless $options{override_permissions};
    foreach my $col ($self->all(%restriction))
    {
        push @columns, $col;
        if ($col->is_curcommon)
        {
            foreach my $c ($col->layout_parent->all(%restriction))
            {
                # No point including autocurs for a filter - it just refers
                # back to the same record, so the filter should be done
                # directly on it instead
                next if $c->type eq 'autocur';
                $c->filter_id($col->id.'_'.$c->id);
                $c->filter_name($col->name.' ('.$c->name.')');
                push @columns, $c;
            }
        }
    }
    @columns;
}

has max_width => (
    is  => 'lazy',
    isa => Int,
);

sub _build_max_width
{   my $self = shift;
    my $max;
    foreach my $col ($self->all)
    {
        $max = $col->width if !$max || $max < $col->width;
    }
    return $max;
}

# Order the columns in the order that the calculated values depend
# on other columns
sub _order_dependencies
{   my ($self, @columns) = @_;

    return unless @columns;

    my %deps = map {
        $_->id => $_->has_display_field ? $_->display_field_col_ids : $_->depends_on
    } @columns;

    my $source = Algorithm::Dependency::Source::HoA->new(\%deps);
    my $dep = Algorithm::Dependency::Ordered->new(source => $source)
        or die 'Failed to set up dependency algorithm';
    my @order = @{$dep->schedule_all};
    map { $self->columns_index->{$_} } @order;
}

sub position
{   my ($self, @position) = @_;
    my $count;
    foreach my $id (@position)
    {
        $count++;
        $self->schema->resultset('Layout')->find($id)->update({ position => $count });
    }
}

sub column
{   my ($self, $id, %options) = @_;
    $id or return;
    my $column = $self->columns_index->{$id}
        or return; # Column does not exist
    return if $options{permission} && !$column->user_can($options{permission});
    $column;
}

# Whether the supplied column ID is a valid one for this instance
sub column_this_instance
{   my ($self, $id) = @_;
    my $col = $self->columns_index->{$id}
        or return;
    $col->instance_id == $self->instance_id;
}

sub _build__columns_namehash
{   my $self = shift;
    my %columns;
    foreach (@{$self->columns})
    {
        next unless $_->instance_id == $self->instance_id;
        error __x"Column {name} exists twice - unable to find unique column",
            name => $_ if $columns{$_};
        $columns{$_->name} = $_;
    }
    \%columns;
}

sub column_by_name
{   my ($self, $name) = @_;
    $self->_columns_namehash->{$name};
}

sub _build__columns_name_shorthash
{   my $self = shift;
    # Include all columns across all instances, except for internal columns of
    # other instances, which will have the same short names as the one from
    # this instance
    my %columns = map { $_->name_short => $_ } grep {
        $_->name_short && (!$_->internal || $_->instance_id == $self->instance_id)
    } @{$self->columns};
    \%columns;
}

sub column_by_name_short
{   my ($self, $name) = @_;
    $self->_columns_name_shorthash->{$name};
}

sub column_id
{   my $self = shift;
    $self->column_by_name_short('_id')
        or panic "Internal _id column missing";
}

# Returns what a user can do to the whole data set. Individual
# permissions for columns are contained in the column class.
sub user_can
{   my ($self, $permission) = @_;
    return 1 if $self->user_permission_override;
    $self->_user_permissions_overall->{$permission};
}

# Whether the user has got any sort of access
sub user_can_anything
{   my $self = shift;
    return 1 if $self->user_permission_override;
    !! keys %{$self->_user_permissions_overall};
}

has referred_by => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build_referred_by
{   my $self = shift;
    [
        $self->schema->resultset('Layout')->search({
            'child.instance_id' => $self->instance_id,
        },{
            join => {
                curval_fields_parents => 'child',
            },
            distinct => 1,
        })->all
    ];
}

has global_view_summary => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build_global_view_summary
{   my $self = shift;
    my @views = $self->schema->resultset('View')->search({
        -or => [
            global   => 1,
            is_admin => 1,
        ],
        instance_id => $self->instance_id,
    },{
        order_by => 'me.name',
    })->all;
    \@views;
}

sub export
{   my $self = shift;
    +{
        name           => $self->name,
        name_short     => $self->name_short,
        homepage_text  => $self->homepage_text,
        homepage_text2 => $self->homepage_text2,
        sort_layout_id => $self->sort_layout_id,
        sort_type      => $self->sort_type,
        permissions    => [ map {
            {
                group_id   => $_->group_id,
                permission => $_->permission,
            }
        } @{$self->_group_permissions} ],
    };
}

sub import_hash
{   my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->instance_id;

    notice __x"Update: name from {old} to {new} for layout {name}",
        old => $self->name, new => $values->{name}, name => $self->name
        if $report && $self->name ne $values->{name};
    $self->name($values->{name});

    notice __x"Update: name_short from {old} to {new} for layout {name}",
        old => $self->name_short, new => $values->{name_short}, name => $self->name
        if $report && ($self->name_short || '') ne ($values->{name_short} || '');
    $self->name_short($values->{name_short});

    notice __x"Update homepage_text for layout {name}", name => $self->name
        if $report && ($self->homepage_text || '') ne ($values->{homepage_text} || '');
    $self->homepage_text($values->{homepage_text});

    notice __x"Update homepage_text2 for layout {name}", name => $self->name
        if $report && ($self->homepage_text2 || '') ne ($values->{homepage_text2} || '');
    $self->homepage_text2($values->{homepage_text2});

    notice __x"Update: sort_type from {old} to {new} for layout {name}",
        old => $self->sort_type, new => $values->{sort_type}, name => $self->name
        if $report && ($self->sort_type || '') ne ($values->{sort_type} || '');
    $self->sort_type($values->{sort_type});

    if ($report)
    {
        my $existing = $self->_group_permissions_hash;
        my $new_hash = {};
        foreach my $new (@{$values->{permissions}})
        {
            $new_hash->{$new->{group_id}}->{$new->{permission}} = 1;
            notice __x"Adding permission {perm} for group ID {group_id}",
                perm => $new->{permission}, group_id => $new->{group_id}
                    if !$existing->{$new->{group_id}}->{$new->{permission}};
        }
        foreach my $old (@{$self->_group_permissions})
        {
            notice __x"Removing permission {perm} from group ID {group_id}",
                perm => $old->permission, group_id => $old->group_id
                    if !$new_hash->{$old->group_id}->{$old->permission};
        }
    }

    $self->set_groups([
        map { $_->{group_id} .'_'. $_->{permission} } @{$values->{permissions}}
    ]);
}

sub import_after_all
{   my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->instance_id;
    my $mapping = $options{mapping};

    if ($values->{sort_layout_id})
    {
        my $new_id = $mapping->{$values->{sort_layout_id}};
        notice __x"Update: sort_layout_id from {old} to {new} for {name}",
            old => $self->sort_layout_id, new => $new_id, name => $self->name
                if $report && ($self->sort_layout_id || 0) != ($new_id || 0);
        $self->sort_layout_id($new_id);
    }
}

sub purge
{   my $self = shift;

    GADS::Graphs->new(schema => $self->schema, layout => $self, current_user => $self->user)->purge;
    GADS::MetricGroups->new(schema => $self->schema, instance_id => $self->instance_id)->purge;
    GADS::Views->new(schema => $self->schema, instance_id => $self->instance_id, user => undef, layout => $self)->purge;

    $_->delete foreach reverse $self->all(order_dependencies => 1, include_hidden => 1);

    $self->schema->resultset('UserLastrecord')->delete;
    $self->schema->resultset('Record')->search({
        instance_id => $self->instance_id,
    },{
        join => 'current',
    })->delete;
    $self->schema->resultset('Current')->search({
        instance_id => $self->instance_id,
    })->delete;
    $self->schema->resultset('InstanceGroup')->search({
        instance_id => $self->instance_id,
    })->delete;
    $self->_rset->delete;
}

sub has_homepage
{   my $self = shift;
       ($self->homepage_text  // '') =~ /\S/
    || ($self->homepage_text2 // '') =~ /\S/;
}

#XXX move to Document
sub all_user_columns {
    my ($class, $site) = @_;
    $site->search(Layout => { internal => 0 })->all;
}

#XXX move to Document
# Returns which field is the newest.
# Warning: Field ids are strictly sequentially assigned.
sub newest_field_id {
    my ($class, $site) = @_;
    $site->search(Layout => { internal => 0 })->get_column('id')->max;
}

1;

