## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Sheet::Layout;

use warnings;
use strict;

use Log::Report 'linkspace';
use List::Util      qw/first max/;
use Scalar::Util    qw/blessed/;
use Linkspace::Util qw/index_by_id/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Linkspace::Column              ();
#use Linkspace::Column::Autocur     ();
use Linkspace::Column::Calc        ();
use Linkspace::Column::Createdby   ();
use Linkspace::Column::Createddate ();
use Linkspace::Column::Curval      ();
use Linkspace::Column::Date        ();
use Linkspace::Column::Daterange   ();
use Linkspace::Column::Deletedby   ();
use Linkspace::Column::Enum        ();
use Linkspace::Column::File        ();
use Linkspace::Column::Id          ();
use Linkspace::Column::Integer     ();
use Linkspace::Column::Person      ();
use Linkspace::Column::Serial      ();
use Linkspace::Column::String      ();
use Linkspace::Column::Tree        ();
#use Linkspace::Column::Rag         ();

my @internal_columns = (
    [ _id               => id          => 1, 'ID' ],
    [ _version_datetime => createddate => 0, 'Last edited time' ],
    [ _version_user     => createdby   => 0, 'Last edited by' ],
    [ _created_user     => createdby   => 0, 'Created by' ],
    [ _deleted_by       => deletedby   => 0, 'Deleted by' ],
    [ _created          => createddate => 0, 'Created time' ],
    [ _serial           => serial      => 1, 'Serial' ],
);

sub internal_columns_show_names { [ map $_->[0], @internal_columns ] }

#------------------
=head1 METHODS: Constructors

=head2 $layout->insert_initial_columns;
When a new sheet is created, its layout get some standard columns.
=cut

sub insert_initial_columns()
{   my ($self) = @_;

    my $position = 0;
    $self->column_create({
        name_short => $_->[0], type => $_->[1], is_unique => $_->[2],
        name => $_->[3], can_child => 0, is_internal => 1, position => ++$position,
    }) for @internal_columns;

    $self;
}

#-------------
=head1 METHODS: Generic Accessors
=cut

has no_overnight_update => ( is => 'ro', isa => Bool );
has default_view_limit_extra => ( is => 'ro');

has sheet => ( is => 'ro', required => 1, weakref  => 1 );

has has_globe => (
    is      => 'lazy',
    builder => sub { !! first { $_->return_type eq 'globe' } @{$_[0]->all_columns} },
);

has has_children => (
    is      => 'lazy',
    builder => sub { !! first { $_->can_child } @{$_[0]->all_columns} },
);

sub as_string(%)
{   my ($self, %args) = @_;
    my $columns = $args{columns} || $self->columns_search(
        exclude_internal => 1,
        sort_by_position => 1,
        %args,
    );
    join '', map sprintf("%2d %s", $_->position, $_->as_string), @$columns;
}

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
    $cols{$_->id} = 1 for grep $_->has_cache, @{$self->all_columns};

    [ keys %cols ];
}

sub columns_for_filter
{   my ($self, %options) = @_;
    my @columns;
    my %restriction = (include_internal => 1, user_can_read => 1);

    foreach my $col ( @{$self->columns(%restriction)} )
    {   push @columns, $col;
        $col->is_curcommon or next;

        my $parent_columns = $col->layout_parent->columns_search(%restriction);
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
    builder => sub { max map $_->width, @{$_[0]->all_columns} },
);

=head2 $layout->reposition(\@order);
Put the columns in the specific order.  Columns which are not listed will
be placed thereafter in their original order.
=cut

sub reposition($)
{   my ($self, $ordered) = @_;
    my @columns  = @{$self->columns($ordered)};

    my $seen     = index_by_id @columns;
    my @other    = grep ! $seen->{$_->id},
        @{$self->columns_search(sort_by_position => 1)};

    my $position = 0;

    $self->column_update($_, { position => ++$position }) for
        +(grep   $_->is_internal, @other),
         @columns,
         (grep ! $_->is_internal, @other);

    $self;
}

#--------------------------------
=head1 METHODS: Permissions

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

sub purge
{   my $self = shift;

    my $guard = $::db->begin_work;
    my $owner = $self->sheet->owner;
    GADS::Graphs->new(layout => $self, current_user => $owner)->purge;
    GADS::MetricGroups->new(instance_id => $self->instance_id)->purge;
    GADS::Views->new(instance_id => $self->instance_id, user => undef)->purge;

    my $columns = $self->columns_search(order_dependencies => 1);
    $self->column_delete($_) for reverse @$columns;

    my %ref_sheet = { instance_id => $self->sheet->id };

    $::db->delete(UserLastrecord => \%ref_sheet);
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
# Warning: Field ids are strictly ordered on age
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
    builder => sub { $_[0]->sheet->document->columns_for_sheet($_[0]->sheet) },
    predicate => 1,
);

=head2 my $column = $layout->column($which, %options);
Find a column by short_name or id.  Local names have preference.
You can check to have a certain permission in one go.
=cut

has _column_index => (
    is      => 'lazy',
    builder => sub {
       my $columns = $_[0]->all_columns;
       +{ map +($_->id => $_, $_->name_short => $_), @$columns };
    },
);

has _document => (is => 'lazy', builder => sub { $::session->site->document });

sub column($)
{   my ($self, $which, %args) = @_;
    defined $which or return;

    # Local names have preference
    my $column = blessed $which ? $which
      : $self->_column_index->{$which} || $self->_document->column($which) || return;

    if(my $p = $args{permission})
    {   $column->user_can($p) or return;
    }

    $column;
}

=head2 \@columns = $layout->columns(\@which, %options);
=cut

sub columns(@)
{   my ($self, $which) = (shift, shift);
    my @columns = map $self->column($_, @_), @$which;
    [ sort { $a->position <=> $b->position } @columns ];
}

=head2 my $column = $layout->column_create(\%insert, %options)
=cut

sub column_create($%)
{   my ($self, $insert, %args) = @_;
    my $sheet  = $insert->{sheet} = $self->sheet;
    $insert->{position} ||= 1 + max map $_->position, @{$self->columns_search};
    my $all    = $self->all_columns;  # be sure to have all before new created

    my $name   = $insert->{name_short} or panic;
    ! $self->_column_index->{$name}
        or error __x"Attempt to create a second column with the same short name '{name}'",
             name => $name;

    my $column = Linkspace::Column->_column_create($insert);

    push @$all, $column if $self->has_all_columns;
    my $index = $self->_column_index;
    $index->{$column->id} = $column;
    $index->{$column->name_short} = $column;
    $sheet->document->publish_column($column);
    $column;
}

=head2 my $column = $layout->column_update($column, \%update, %options);
Change the content of a column.
=cut

sub column_update($%)
{   my ($self, $which, $update, %args) = @_;
    my $column = $self->column($which) or panic $which;

    my $old_name = $column->name_short;
    my $new_name = $update->{name_short};
    error __x"Attempt to rename column '{old}' into existing name '{name}'",
       old => $old_name, name => $new_name
       if $new_name && $new_name ne $old_name && $self->column($new_name);

    $column->_column_update($update, %args);

    if($new_name)
    {   my $index = $self->_column_index;
        delete $index->{$old_name};
        $index->{$column->name_short} = $column;
        $self->sheet->document->publish_column($column);
    }

    $column;
}

=head2 \@cols = $layout->columns_search(%options);
=cut

my %filters_invariant = (
    exclude_internal => sub { ! $_[0]->is_internal },
    only_internal    => sub {   $_[0]->is_internal },
    only_unique      => sub {   $_[0]->is_unique },
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
    type       => sub { $_[0]->type          eq $_[1] },
    remember   => sub { $_[0]->do_remember   == $_[1] },
    userinput  => sub { $_[0]->is_userinput  == $_[1] },
    multivalue => sub { $_[0]->is_multivalue == $_[1] },
    topic      => sub { $_[0]->topic_id      == $_[1] },
);

# Order the columns in the order that the calculated values depend
# on other columns
sub _ordered_dependencies
{   my ($self, @columns) = @_;
    @columns or return;

    my %deps  = map +($_->id => $_->dependencies_ids), @columns;
    my $source = Algorithm::Dependency::Source::HoA->new(\%deps);
    my $dep    = Algorithm::Dependency::Ordered->new(source => $source)
        or die 'Failed to set up dependency algorithm';

    [ map $self->column_by_id($_), @{$dep->schedule_all} ];
}

sub columns_search
{   my ($self, %args) = @_;
    keys %args or return [ @{$self->all_columns} ];

    if(exists $args{topic_id})
    {   if(my $topic = delete $args{topic_id})
             { $args{topic} = $topic }
        else { $args{without_topic} = 1 }
    }

    my @filters;
    foreach my $flag (keys %args)
    {   if(my $f = $filters_invariant{$flag})
        {   # A simple filter, based on the layout alone
            push @filters, $f if $args{$flag};
            delete $args{$flag};
        }
        elsif(my $g = $filters_compare{$flag})
        {   # Filter based on comparison
            if(defined(my $need = $args{$flag}))
            {   push @filters, sub { $g->($_[0], $need) };
            }
            delete $args{$flag};
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

    my $columns;
    if(delete $args{order_dependencies})
    {   $columns = $self->_ordered_dependencies(@columns);
    }
    elsif(delete $args{sort_by_topics})
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
                {   push @$columns, $_;
                    $done{$_->id}++;
                }
            }
            else
            {   push @$columns, $col;
            }
            $previous_topic_id = $col->topic_id || 0;
        }
    }
    elsif(delete $args{sort_by_position})
    {   $columns = [ sort { $a->position <=> $b->position } @columns ];
    }
    else
    {   $columns = \@columns;
    }

    panic $_ for keys %args;

    \@columns;
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
{   my ($self, $which) = @_;
    my $column = $self->column($which) or panic;
    my $doc   = $self->sheet->document;

    # First see if any views are conditional on this field
    my $monitoring = Linkspace::Column::DisplayFilter::Rule->monitoring($column);
    if(@$monitoring)
    {   my @names = map $_->name, @{$self->columns($monitoring)};
        error __x"The following columns are conditional on this field: {dep}.
            Please remove these display rules first.", dep => \@names;
    }

=pod

    my $depending = $doc->columns($column->depends_on);
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
=cut

    $doc->column_unuse($column);
    $column->remove_history;

    my $index = $self->_column_index;
    $index->{$column->id} = undef;
    $index->{$column->name_short} = undef;

    $column->delete;
}

sub sheet_unuse()
{   my ($self) = @_;
    $self->column_delete($_) for @{$self->all_columns};
    # Layout has no substance itself
}

sub topic_unuse($)
{   my ($self, $topic) = @_;
    $topic or return;
    $::db->update(Layout => { topic_id => $topic->id }, { topic_id => undef });
}

#-----------------------
=head1 METHODS: for Document

=head2 my @cols = $class->load_columns($site);
Initially load all column information for a certain site.  For the whole
site!  This is required because sheets do interlink.  For instance,  we
need to be able to lookup columns names in Filters.
=cut

sub load_columns($)
{   my ($class, $site) = @_;

    my $cols = $::db->search(Layout => {
        'instance.site_id' => $site->id,
    },{
        join     => 'instance',
    });

    [ map Linkspace::Column->from_record($_), $cols->all ];
}

#-----------------------
=head1 METHODS: REST interface
=cut

has api_index_layout => (
    is      => 'lazy',
    builder => sub { $_[0]->column($_[0]->api_index_layout_id) },
);

has api_index_layout_id => (
    is      => 'ro',
    isa     => Maybe[Int],
);

1;
