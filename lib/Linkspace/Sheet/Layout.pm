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

package Linkspace::Sheet::Layout;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use Log::Report 'linkspace';
use List::Util  qw/first max/;

#use Linkspace::Column ();

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

has default_view_limit_extra => (
    is      => 'ro',
);

has api_index_layout => (
    is      => 'lazy',
    builder => sub { $_[0]->column($_[0]->api_index_layout_id) },
);

has api_index_layout_id => (
    is      => 'ro',
    isa     => Maybe[Int],
);

#------------------
=head1 METHODS: Constructors

=head2 my $layout_id = $class->layout_create(%insert);
=cut

# initial Columns for a new sheet.
my @internal_columns = (
    {   name        => 'ID',
        type        => 'id',
        name_short  => '_id',
        isunique    => 1,
    },
    {   name        => 'Last edited time',
        type        => 'createddate',
        name_short  => '_version_datetime',
        isunique    => 0,
    },
    {   name        => 'Last edited by',
        type        => 'createdby',
        name_short  => '_version_user',
        isunique    => 0,
    },
    {   name        => 'Created by',
        type        => 'createdby',
        name_short  => '_created_user',
        isunique    => 0,
    },
    {   name        => 'Deleted by',
        type        => 'deletedby',
        name_short  => '_deleted_by',
        isunique    => 0,
    },
    {   name        => 'Created time',
        type        => 'createddate',
        name_short  => '_created',
        isunique    => 0,
    },
    {   name        => 'Serial',
        type        => 'serial',
        name_short  => '_serial',
        isunique    => 1,
    },
);

sub layout_create(%)
{    my ($class, %insert) = @_;
     my $sheet_id = delete $insert{sheet_id};

     foreach my $col (@internal_columns)
     {   $::db->create(Layout => {
             %$col,
             can_child   => 0,
             internal    => 1,
             instance_id => $sheet_id,
         });
     }
}

sub layout_update($)
{   my ($self, %update) = @_;

    my $permissions = delete $update{permissions};

    $self->set_permissions($permissions)
         if $self->groups;

    $self;
}

=head2 my @cols = $class->load_columns;
Initially load all column information for a certain site.  For the whole
site!  This is required because sheets do interlink.  For instance,  we
need to be able to lookup columns names in Filters.
=cut

sub load_columns($)
{   my ($class, $site) = @_;

    my $cols = $::db->search(Layout => {
        'instance.site_id' => $site->id,
    },{
        select   => 'me.*',
        join     => 'instance',
#XXX do not prefetch for performance?
        prefetch => [ qw/calcs rags link_parent display_fields/ ],
        result_class => 'HASH',
    });

    [ $cols->all ];
}

has has_globe => (
    is      => 'lazy',
    builder => sub { !! first { $_->return_type eq 'globe' } @{$_[0]->all_columns} },
);

has has_children => (
    is      => 'lazy',
    builder => sub { !! first { $_->can_child } $_[0]->all_columns },
);

# All the column IDs needed to update all cached fields. This is all the
# calculated/rag fields, plus any fields that they depend on
sub col_ids_for_cache_update
{   my $self = shift;
    my $sheet_id = $self->sheet->id;

    # First all the "parent" fields (the calc/rag fields)
    my %cols = map +($_ => 1), $::db->search(LayoutDepend => {
        instance_id => $sheet_id,
    },{
        join     => 'layout',
        group_by => 'me.layout_id',
    })->get_column('layout_id')->all;

    # Then all the fields they depend on
    $cols{$_} = 1 for $::db->search(LayoutDepend => {
        instance_id => $sheet_id,
    },{
        join     => 'depend_on',
        group_by => 'me.depends_on',
    })->get_column('depends_on')->all;

    # Finally ensure all the calc/rag fields are included. If they only use an
    # internal column, then they won't have been part of the layout_depend
    # table
    $cols{$_->id} = 1 for grep $_->has_cache, $self->all_columns;

    [ keys %cols ];
}

sub all_with_internal
{   my $self = shift;
    $self->columns(@_, include_internal => 1);
}

sub columns_for_filter
{   my ($self, %options) = @_;
    my @columns;
    my %restriction = (include_internal => 1);
    $restriction{user_can_read} = 1 unless $options{override_permissions};

    foreach my $col ( @{$self->columns(%restriction)} )
    {   push @columns, $col;
        $col->is_curcommon or next;

        my $parent_columns = $col->layout_parent->columns(%restriction);
        foreach my $c (@$parent_columns)
        {   # No point including autocurs for a filter - it just refers
            # back to the same record, so the filter should be done
            # directly on it instead
            next if $c->type eq 'autocur';

            $c->filter_id($col->id.'_'.$c->id);
            $c->filter_name($col->name.' ('.$c->name.')');
            push @columns, $c;
        }
    }
    @columns;
}

has max_width => (
    is      => 'lazy',
    builder => sub { max map $_->width, $_[0]->all_columns },
);

sub reposition
{   my ($self, @column_ids) = @_;
    my $col_nr = 0;
    foreach my $col_id (@column_ids)
    {   $::db->update(Layout => $_, { position => ++$col_nr });
        $self->column($col_id)->position($col_nr);
    }
}

sub contains_column($)
{   my ($self, $column) = @_;
    !! $self->columns_index->{$column->id};
}

# Returns what a user can do to the whole data set. Individual
# permissions for columns are contained in the column class.
sub user_can
{   my ($self, $permission) = @_;
    $self->_user_permissions_overall->{$permission};
}

# Whether the user has got any sort of access
sub user_can_anything
{   my $self = shift;
    !! keys %{$self->_user_permissions_overall};
}

has referred_by => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub
    {   my $self = shift;
        my $refd = $::db->search(Layout => {
            'child.instance_id' => $self->sheet->id
        },{
            join => { curval_fields_parents => 'child' },
            distinct => 1,
        });
        [ $refd->all ];
    },
);

has global_view_summary => (
    is      => 'lazy',
    isa     => ArrayRef,
);

sub _build_global_view_summary
{   my $self = shift;
    my $views = $::db->search(View => {
        -or => [ global => 1, is_admin => 1 ],
        instance_id => $self->sheet->id,
    },{
        order_by => 'me.name',
    });

    [ $views->all ];
}

sub export
{   my $self = shift;

    my @perms = map +{
        group_id   => $_->group_id,
        permission => $_->permission,
    }, @{$self->_group_permissions};

     +{
        name           => $self->name,
        name_short     => $self->name_short,
        homepage_text  => $self->homepage_text,
        homepage_text2 => $self->homepage_text2,
        sort_layout_id => $self->sort_layout_id,
        sort_type      => $self->sort_type,
        permissions    => \@perms,
     };
}

#XXX must disappear: Layout object immutable
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
        map "$_->{group_id} .'_'. $_->{permission}", @{$values->{permissions}}
    ]);
}

sub purge
{   my $self = shift;

    my $guard = $::db->begin_work;
    GADS::Graphs->new(layout => $self, current_user => $self->user)->purge;
    GADS::MetricGroups->new(instance_id => $self->instance_id)->purge;
    GADS::Views->new(instance_id => $self->instance_id, user => undef)->purge;

    $_->delete for reverse
        @{$self->columns(order_dependencies => 1, include_hidden => 1)};

    my %ref_sheet = { instance_id => $self->sheet->id };

    $::db->resultset('UserLastrecord')->delete;   # empty table

    $::db->delete(Record        => \%ref_sheet, { join => 'current' });
    $::db->delete(Current       => \%ref_sheet);
    $::db->delete(InstanceGroup => \%ref_sheet);

    $self->delete;
    $guard->commit;
}

sub has_homepage
{   my $self = shift;
       ($self->homepage_text  // '') =~ /\S/
    || ($self->homepage_text2 // '') =~ /\S/;
}

#XXX move to Document
# Returns which field is the newest.
# Warning: Field ids are strictly sequentially assigned.
sub newest_field_id {
    my ($class, $site) = @_;
    $::db->search(Layout => { internal => 0 })->get_column('id')->max;
}

#-------------------------
=head1 METHODS: Column management
Column definitions are shared between all Sheets in a Document: a
Layout maintains is a subset of these definitions.

=head2 \@cols = $layout->all_columns;
=cut

# Sometimes, the structure is build downside-up: from column into
# a sheet.
has all_columns => (
    is      => 'lazy',
    builder => sub { $_[0]->document->columns_for_sheet($_[0]->sheet) },
);

=head2 my $column = $layout->column($which, %options);
Find a column by short_name or id.  Local names have preference.
You can check to have a certain permission in one go.
=cut

has _column_index => (
    is      => 'lazy',
    builder => sub {
       my $columns = $_[0]->all_columns;
       +{ map +($_->id => $_, $_->short_name => $_), @$columns };
    },
);

sub column($)
{   my ($self, $which) = (shift, shift);
    return $which if blessed $which;

    # Local names have preferenx
    my $column = $self->_column_index->{$which}
        or return $self->document->column($which, @_);

    @_ or return $column;
    my %args = @_;
    ! $args{permission} || $column->user_can($args{permission}) ? $column : undef;
}

=head2 $layout->column_create(%insert)
=cut

sub column_create($)
{   my ($self, %insert) = @_;
    my $impl_class = delete $insert{impl_class}
      || Linkspace::Column->type2class($insert{type});

    $insert{instance_id} = $self->sheet->id;

    $::db->begin_work;
    my $column_id = $impl_class->column_create(\%insert);
    my $column    = Linkspace::Column->from_id($column_id, layout => $self);
    $::db->commit;

    $self->sheet->document->publish_column($column);

    push @{$self->all_columns}, $column;
    my $index = $self->_column_index;
    $index->{$column_id} = $column;
    $index->{$column->short_name} = $column;
    $column;
}

=head2 \@cols = $layout->columns(%options);
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

    my %deps  = map +($_->id => $_->dependencies_ids), @columns;
    my $source = Algorithm::Dependency::Source::HoA->new(\%deps);
    my $dep    = Algorithm::Dependency::Ordered->new(source => $source)
        or die 'Failed to set up dependency algorithm';

    map $self->column_by_id($_), @{$dep->schedule_all};
}

sub columns
{   my ($self, %options) = @_;
    keys %options or return $self->all_columns;

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

    my @columns  = grep $filter->($_), @{$self->all_columns};

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
        {   next if $done{$col->id}++;
            if($col->topic_id && $col->topic_id != $previous_topic_id)
            {   foreach (@{$topics{$col->topic_id}})
                {   push @new, $_;
                    $done{$_->id}++;
                }
            }
            else
            {   push @new, $col;
            }
            $previous_topic_id = $col->topic_id || 0;
        }
        return \@new;
    }

    return [ sort { $a->position <=> $b->position } @columns ]
        if $options{sort_by_position};

    \@columns;
}

=head2 my $last = $layout->highest_position;
Returns the highest position number in use.
=cut

sub highest_position()
{   my $columns = shift->columns(include_hidden => 1, sort_by_position => 1) || [];
    @$columns ? $columns->[-1]->position : 0;
}

=head2 $layout->column_unuse($which);
Remove all kinds of usage for this column, maybe to delete it later.
=cut

sub column_unuse($)
{   my ($self, $which) = @_;
    my $col_id = blessed $which ? $which->id : $which;

    my $col_ref = { layout_id => $col_id };
    $::db->delete($_ => $col_ref)
        for qw/DisplayField LayoutDepend LayoutGroup/;
    $self;
}

=head2 $layout->column_delete($column);
Remove this column everywhere.
=cut

sub column_delete($)
{   my ($self, $column) = @_;
    my $doc   = $self->document;

    # First see if any views are conditional on this field
    my $disps = $column->display_fields;

    if(@$disps)
    {   my @names = map $_->layout->name, @$disps;   #XXX???
        error __x"The following fields are conditional on this field: {dep}.
            Please remove these conditions before deletion.", dep => \@names;
    }

    my $depending = $doc->columns($column->depended_by_ids);
    if(@$depending)
    {   error __x"The following fields contain this field in their formula: {dep}.
            Please remove these before deletion.",
            dep => [ map $_->name_long, @$depending ];
    }

    my $parents = $doc->columns_refering_to($column);
    if(@$parents)
    {   error __x"The following fields in another table refer to this field: {p}.
            Please remove these references before deletion of this field.", 
            p => [ map $_->parent->name_long, @$parents ];
    }

    # Now see if any linked fields depend on this one
    my $childs = $doc->columns_link_child_of($column);
    if(@$childs)
    {   error __x"The following fields in another table are linked to this field: {l}.
            Please remove these links before deletion of this field.",
            l => [ map $_->name_long, @$childs ];
    }

    my @graphs = grep $_->uses_column($column), @{$self->sheet->graphs->all_graphs};
    if(@graphs)
    {
        error __x"The following graphs references this field: {graph}. Please update them before deletion.",
            graph => [ map $_->title, @graphs ]; 
    }

    my $guard = $::db->begin_work;
    $doc->column_unuse($column);
    $column->remove_history;
    $column->delete;    # Finally!

    $guard->commit;
}

sub sheet_unuse($)
{   my ($self, $sheet) = @_;

    $self->column_delete($_) for $self->all_columns;
    # I have no substance
}

sub topic_unuse($)
{   my ($self, $topic) = @_;
    $topic or return;
    $::db->update(Layout => { topic_id => $topic->id }, { topic_id => undef });
}

1;

