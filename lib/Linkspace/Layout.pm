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

package Linkspace::Layout;

use Log::Report 'linkspace';

use GADS::Column;
use GADS::Graphs;
use GADS::MetricGroups;
use GADS::Views;
use String::CamelCase qw(camelize);

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

has name => (
    is      => 'rw',
    isa     => Str,
);

has name_short => (
    is      => 'rw',
    isa     => Maybe[Str],
);

has identifier => (
    is      => 'ro',
);

has homepage_text => (
    is      => 'ro',
    isa     => Maybe[Str],
);

has homepage_text2 => (
    is      => 'rw',
    isa     => Maybe[Str],
);

has forget_history => (
    is      => 'ro',
    isa     => Bool,
);

has forward_record_after_create => (
    is      => 'ro',
    isa     => Bool,
);

has no_hide_blank => (
    is      => 'ro',
    isa     => Bool,
);

has no_overnight_update => (
    is      => 'ro',
    isa     => Bool,
);

has sort_layout_id => (
    is      => 'rw',
    isa     => Maybe[Int],
);

has default_view_limit_extra => (
    is      => 'ro',
);

has default_view_limit_extra_id => (
    is      => 'ro',
    isa     => Maybe[Int],
);

has api_index_layout => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->column($self->api_index_layout_id);
    },
    clearer => 1,
);

has api_index_layout_id => (
    is      => 'ro',
    isa     => Maybe[Int],
);

has sort_type => (
    is      => 'rw',
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
);

has _columns_name_shorthash => (
    is      => 'lazy',
    isa     => HashRef,
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
    my $user_perms = $::db=>search(User => {
        'me.id'              => $user_id,
    },
    {
        prefetch => {
            user_groups => {
                group => { layout_groups => 'layout' },
            }
        },
        result_class => 'HASH',
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

    $sheet->set_permissions($self->set_groups);
        if $self->has_set_groups;

    $self;
}

=head2 $class->create_for_sheet($sheet);
Create the initial Columns for a new sheet.
=cut

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

sub create_for_sheet($)
{   my ($class, $sheet) = @_;
    my $sheet_id = $sheet->id;

	my $guard = $::db->begin_work;

    foreach my $col (@internal_columns)
    {   $::db->create(Layout => {
            %$col,
            can_child   => 0,
            internal    => 1,
            instance_id => $sheet_id,
        });
    }

	$guard->commit;
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
        result_class => 'HASH',
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
    $::db->search(Layout => { internal => 0 })->all;
}

#XXX move to Document
# Returns which field is the newest.
# Warning: Field ids are strictly sequentially assigned.
sub newest_field_id {
    my ($class, $site) = @_;
    $::db->search(Layout => { internal => 0 })->get_column('id')->max;
}

=head1 METHODS: Column management
Column definitions are shared between all Sheets in a Document: a
Layout maintains is a subset of these definitions.

=head2 \@cols = $layout->columns;
=cut

has columns => (
    is    => 'lazy',
    isa   => ArrayRef,
    builder => sub {
        [ map Linkspace::Column->from_id($_), $_[0]->column_ids ]
    },
);

=head2 \@col_ids = $layout->column_ids;
=cut

has column_ids => (
    is    => 'lazy',
    isa   => ArrayRef,
    builder => sub { $_[0]->document->columns_for_layout($_[0]) },
}

=head2 $col = $layout->column_by_id($id);
=cut

has _column_by_id => (
    is      => 'lazy',
    isa     => HashRef,
    builder => sub {
}

sub column_by_id($)
{   my ($self, $id) = @_;
    $self->_column_by_id->{$id};
}

=head2 \@cols = $layout->search_columns(%options);
=cut

my %filters_invariant = (
    exclude_hidden   => sub { ! $_[0]->hidden },
    exclude_internal => sub { ! $_[0]->internal },
    only_internal    => sub {   $_[0]->internal },
    only_unique      => sub {   $_[0]->isunique },
    can_child        => sub {   $_[0]->can_child },
    linked           => sub {   $_[0]->link_parent },
    is_globe         => sub {   $_[0]->return_type eq 'globe' },
    has_cache        => sub {   $_[0]->has_cache },
    user_can_read    => sub {   $_[0]->user_can('read') },
    user_can_write   => sub {   $_[0]->user_can('write') },
    without_topic    => sub { ! $_[0]->topic_id },
    user_can_write_new          => sub { $_[0]->user_can('write_new') },
    user_can_write_existing     => sub { $_[0]->user_can('write_existing') },
    user_can_readwrite_existing =>
        sub { $_[0]->user_can('write_existing') || $_[0]->user_can('read') },
    user_can_approve_new        => sub { $_[0]->user_can('approve_new') },
    user_can_approve_existing   => sub { $_[0]->user_can('approve_existing') },
);

my %filters_compare = (
    type       => sub { $_[0]->type       eq $_[1] },
    remember   => sub { $_[0]->remember   == $_[1] },
    userinput  => sub { $_[0]->userinput  == $_[1] },
    multivalue => sub { $_[0]->multivalue == $_[1] },
    topic      => sub { $_[0]->topic_id   == $_[1] },
);

# Order the columns in the order that the calculated values depend
# on other columns
sub _order_dependencies
{   my ($self, @columns) = @_;
    @columns or return;

    my %deps  = map +($_->id => $_->dependencies), @columns;
    my $source = Algorithm::Dependency::Source::HoA->new(\%deps);
    my $dep    = Algorithm::Dependency::Ordered->new(source => $source)
        or die 'Failed to set up dependency algorithm';

    map $self->column_by_id($_), @{$dep->schedule_all};
}

sub search_columns
{   my ($self, %options) = @_;

    # Some parameters are a bit inconvenient
    $options{exclude_hidden} = ! delete $options{include_hidden}
        if exists $options{include_hidden};

    if(exists $options{topic_id})
    {   if(my $topic = delete $options{topic_id})
             { $options{topic} = $topic }
        else { $options{without_topic} = 1 }
    }

    my @filters;
    foreach my $flag (keys %options)
    {
        if(my $f = $filters_invariant{$flag})
        {   # A simple filter, based on the layout alone
            push @filters, $f if $options{$flag};
        }
        elsif(my $g = $filters_compare{$flag})
        {   # Filter based on comparison
            if(defined(my $need = $options{$flag}))
            {   push @filters, sub { $g->($_[0], $need) };
            }
        }
    }

    my $filter
      = !@filters   ? sub { 1 }
      : @filters==1 ? $filters[0]
      : sub {
            my $v = shift;
            $_->($v) || return 0 for @filters;
            1;
        };

    my @columns  = grep $filter->($_), @{$self->columns};

    @columns = $self->_order_dependencies(@columns)
        if $options{order_dependencies};

    if($options{sort_by_topics})
    {
        # Sorting by topic involves keeping the order of fields that do not
        # have a defined topic, but slotting in those together that have the
        # same topic.

        # First build up an index of topics and their fields
        my %topics;
        foreach my $col (@columns)
        {   my $topic = $col->topic_id or next;
            push @{$topics{$topic}}, $col;
        }

        my @new; my $previous_topic_id = 0; my %done;
        foreach my $col (@columns)
        {
            next if $done{$col->id};
            $done{$col->id} = 1;
            if ($col->topic_id && $col->topic_id != $previous_topic_id)
            {   foreach (@{$topics{$col->topic_id}})
                {   push @new, $_;
                    $done{$_->id} = 1;
                }
            }
            else {
                push @new, $col;
                $done{$col->id} = 1;
            }
            $previous_topic_id = $col->topic_id || 0;
        }
        @columns = @new;
    }

    @columns;
}

1;

