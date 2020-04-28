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

package Linkspace::View;

use Log::Report 'linkspace';
use MIME::Base64;
use String::CamelCase qw(camelize);

use List::Util qw(first);
use Linkspace::View::Alert;
use Linkspace::Filter;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'Linkspace::DB::Table';

sub db_table { 'View' }
sub db_field_rename { +{
    filter      => 'filter_json',
    instance_id => 'sheet_id',
    global      => 'is_global',
} };

### 2020-04-16: columns in GADS::Schema::Result::View
# id             user_id        group_id
# instance_id    filter         is_admin
# name           global         is_limit_extra

use namespace::clean;

=head1 NAME

Linkspace::View - rules to sub-set sheet data.

=head1 SYNOPSIS

=head1 DESCRIPTION
A user's View restricts the data in a sheet according to rules.  Applying
the view on the data results in a Page.

=head1 METHODS: constructors

=head2 my $view = $class->new(%options);
=cut

sub BUILD
{   my ($self, $args) = @_;
    my $sheet = $args->{sheet} or panic;
    $args->{user_can_layout} = $sheet->user_can('layout');
}

=head2 my $view = $class->from_id($view_id, %options);
Reinstantiate an existing view, based on its C<$view_id>.  The
C<%options> are passed to the constructor.
=cut

sub from_id($%)
{   my ($class, $view_id) = (shift, shift);

    my $record = $::db->search(View => {
        'me.id' => $self->id
    },{ 
        prefetch => ['sorts', 'alerts', 'view_groups'],
        order_by => 'sorts.order', # sorts in correct order to apply
    })->first;

	$class->new(%$record);
}

has filter => (
    is      => 'rw',
    lazy    => 1,
    coerce  => sub {
        my $value = shift;
        if (ref $value ne 'GADS::Filter')
        {   my $format = ref $value eq 'HASH' ? 'as_hash' : 'as_json';
            $value = GADS::Filter->new($format => $value);
        }
        $value;
    },
    builder => sub {
        my $self = shift;
        my $filter = $self->_view # Don't trigger changed() in Filter
            ? GADS::Filter->new(layout => $self->layout, as_json => $self->_view->filter)
            : GADS::Filter->new(layout => $self->layout);
    },
);

has sorts => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { $_[0]->_get_sorts || [] },
);

has groups => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { [ $_[0]->view_groups->all ] },
);

#XXX see ::Records::current_group_id()
sub first_column_id()
{    my $groups = $self->groups;
     @$groups ? $groups->[0]->layout_id : undef;
}

has alert => (
    is      => 'rw',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        my $user_id = $::session->user->id;
        first { $user_id == $_->user_id } $self->alerts;
    }
);

has has_alerts => (
    is      => 'lazy',
    isa     => Bool,
    builder => sub { $_[0]->alerts->count ? 1 : 0 },
);

has column_ids => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { [ map $_->layout_id, $self->view_layouts ] },
);

# Whether the view has a variable "CURUSER" condition
has has_curuser => (
    is      => 'lazy',
    isa     => Bool,
);

sub _build_has_curuser
{   my $self = shift;
    my $layout = $self->sheet->layout;
    !! grep {
        my $col = $layout->column($_->{column_id});

        ($col->type eq 'person' || $col->return_type eq 'string')
        && $_->{value} && $_->{value} eq '[CURUSER]')
    } @{$self->filter->filters};
}

has owner => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $::linkspace->users->user($_[0]->user_id) },
);

sub has_access_via_global($)
{   my ($self, $victim) = @_;
    my $gid = $self->group_id;
    $gid && $self->is_global ? $victim->in_group($gid) : 0;
}

sub _is_writable($;$)
{   my ($self, $sheet, $victim) = @_;
    $victim ||= $::session->user;
    my $owner_id = $self->user_id;

#XXX this is a bit weird... usually, the ways to get access work
#XXX in parallel

    if($self->is_admin)
    {   return 1 if $sheet->user_can(sheet => $victim);
    }
    elsif($self->is_global)
    {   return 1 if !$self->group_id && $sheet->user_can(sheet => $victim);
        return 1 if  $self->group_id && $sheet->user_can(view_group => $victim);
    }
    elsif($owner_id && $owner_id == $victim->id)
    {   return 1 if $sheet->user_can(view_create => $victim);
    }
    else
    {   return 1 if $sheet->user_can(sheet => $victim);
    }

    0;
}

sub _sorts($$)
{    my ($self, $fields, $types) = @_;
#TODO move code from write() here
}

sub view_update
{   my ($self, %update) = @_;

    length $update{name} < 128
        or error __"View name must be less than 128 characters";

    my $col_ids = delete $update{column_ids} || [];
    $col_ids    = [ $col_ids ] if ref $col_ids eq 'ARRAY';

    my $sheet   = delete $update{sheet};
    $update{instance_id} = $sheet->id;

    if($update{global} || $update{is_admin})
    {   $update{user_id} = undef;
    }
    elsif(! $self->user_id && $sheet->user_can('layout'))
    {   # Preserve owner if editing other user's view
        $update{user_id} = $::session->user->id
    }

    my $filter = Linkspace::Filter->from_json($update{filter}, view => $self);
    $update{filter} = $filter->as_json if $filter;

    $::session->user->isa('Linkspace::User::Person')
        or $update{global} = 1;

    my $guard = $::db->begin_work;

    $self->_update_column_ids($col_ids);
    $self->_sorts(delete $update{sortfields}, $update{sorttypes});
    $self->_groups(delete $update{groups});
    $self->_filter($filter);

    $::db->update(View => $self->id, \%update);
    $guard->commit;
}

sub write
{   my ($self, $sheet, %options) = @_;

    my $fatal = $options{no_errors} ? 0 : 1;

    $self->name or error __"Please enter a name for the view";

    # XXX Database schema currently restricts length of name. Should be changed
    # to normal text field at some point
    length $self->name < 128
        or error __"View name must be less than 128 characters";

    my $global   = ! $sheet->user ? 1 : $self->is_global;

    my $vu = {
        name        => $self->name,
        filter      => $self->filter->as_json,
        instance_id => $sheet->id,
        global      => $global,
        is_admin    => $self->is_admin,
        group_id    => $self->group_id,
    };

    if($global || $self->is_admin)
    {   $vu->{user_id}  = undef;
    }
    elsif(! $self->user_id && $self->user_can('layout'))
    {   $vu->{user_id} = $::session->user->id;
    }

    # Get all the columns in the filter. Check whether the user has
    # access to them.
    foreach my $filter (@{$self->filter->filters})
    {   my $col_id = $filter->{column_id};
        my $col    = $self->column($col_id)
            or error __x"Field ID {id} does not exist", id => $col_id
        my $val   = $filter->{value};
        my $op    = $filter->{operator};
        my $rtype = $col->return_type;
        if ($rtype eq 'daterange')
        {   if ($op eq 'equal' || $op eq 'not_equal')
            {
                # expect exact daterange format, e.g. "yyyy-mm-dd to yyyy-mm-dd"
                $col->validate_search($val, fatal => $fatal, full_only => 1); # Will bork on failure
            }
            else
            {   $col->validate_search($val, fatal => $fatal, single_only => 1); # Will bork on failure
            }
        }
        elsif($op ne 'is_empty' && $op ne 'is_not_empty')
        {   # 'empty' would normally fail on blank value
            $col->validate_search($val, fatal => $fatal) # Will bork on failure
        }

        my $has_value = $val && (ref $val ne 'ARRAY' || @$val);
        error __x "No value can be entered for empty and not empty operators"
            if $has_value && ($op eq 'is_empty' || $op eq 'is_not_empty');

        $col->user_can('read')
             or error __x"Invalid field ID {id} in filter", id => $col->id;
    }

    my $user = $::session->user;
    $self->writable($sheet)
        or error $self->id
            ? __x("User {user_id} does not have access to modify view {id}", user_id => $user->id, id => $self->id)
            : __x("User {user_id} does not have permission to create new views", user_id => $user->id);

    $self->SUPER::update($vu);

    # Update any alert caches for new filter
    if ($self->filter->changed && $self->has_alerts)
    {
        my $alert = GADS::Alert->new(
            view_id   => $self->id,
        );
        $alert->update_cache;
    }
    else {
        my $rset = $::db->create(View => $vu);
XXX caller must reinstate full View.
    }

    my @colviews = @{$self->column_ids};

    my $columns = $sheet->layout->columns_search(user_can_read => 1);
    foreach my $c (@$columns)
    {
        my %item = (view_id => $self->id, layout_id => $c->id);

        if (grep $c->id == $_, @colviews)
        {
            # Column should be in view
            unless($::db->search(ViewLayout => \%item)->count)
            {
                $::db->create(ViewLayout => $item);

                # Update alert cache with new column
                my $alerts = $::db->search(View => {
                    'me.id' => $self->id,
                }, {
                    columns  => [
                        { 'me.id'  => \"MAX(me.id)" },
                        { 'alert_caches.id'  => \"MAX(alert_caches.id)" },
                        { 'alert_caches.current_id'  => \"MAX(alert_caches.current_id)" },
                    ],
                    join     => 'alert_caches',
                    group_by => 'current_id',
                });

                my @pop;
                foreach my $alert ($alerts->all)
                {
                    push @pop, map +{
                        layout_id  => $c->id,
                        view_id    => $self->id,
                        current_id => $_->current_id,
                    }, $alert->alert_caches;
                }
                $::db->resultset('AlertCache')->populate(\@pop) if @pop;
            }
        }
    }

    # Delete any no longer needed
    my $search = {view_id => $self->id};
    $search->{'-not'} = {layout_id => \@colviews} if @colviews;
    $::db->delete(ViewLayout => $search);
    $::db->delete(AlertCache => $search);

    # Then update the filter table, which we use to query what fields are
    # applied to a view's filters when doing alerts.
    # We don't sanitise the columns the user has visible at this point -
    # there is not much point, as they could be removed later anyway. We
    # do this during the processing of the alerts and filters elsewhere.
    my @existing = $::db->search(Filter => { view_id => $self->id })->all;

    my @all_filters = @{$self->filter->filters};
    foreach my $filter (@all_filters)
    {
        unless (grep $_->layout_id == $filter->{column_id}, @existing)
        {
            # Unable to add internal columns to filter table, as they don't
            # reference any columns from the layout table  XXX old
            next unless $filter->{column_id} > 0;

            $::db->create(Filter => {
                view_id   => $self->id,
                layout_id => $filter->{column_id},
            });
        }
    }
    # Delete those no longer there
    my %search2 = ( view_id => $self->id );
    $search2{layout_id} = { '!=' => [ '-and', map $_->{column_id}, @all_filters ] }
         if @all_filters;
    $::db->delete(Filter => \%search);
}

sub delete($)
{   my ($self, $sheet) = @_;

    $self->writable($sheet)
        or error __x"You do not have permission to delete {id}", id => $self->id;
    my $vl = $::db->search(ViewLimit => {
        view_id => $self->id,
    },{
        prefetch => 'user',
    });

    if ($vl->count)
    {
        my $users = join '; ', $vl->get_column('user.value')->all;
        error __x"This view cannot be deleted as it is used to limit user data. Remove the view from the limited views of the following users before deleting: {users}", users => $users;
    }

    my $view = $self->_view
        or return; # Doesn't exist. May be attempt to delete view not yet written

    my $ref_view = { view_id => $view->id };
    $::db->delete($_ => $ref_view)
        for qw/Sort ViewLayout ViewGroup Filter AlertCache/;

    my @alerts    = $::db->search(Alert => $ref_view)->get_column('id')->all;
    my @alert_ids = map $_->id, @alerts;
    $::db->delete(AlertSend => { alert_id => \@alert_ids });
    $::db->delete(Alert => { id => \@alert_ids });

    $::db->update(User => { lastview => $view->id }, { lastview => undef });
    $view->delete;
}

sub sort_types
{
    [
        {
            name        => "asc",
            description => "Ascending"
        },
        {
            name        => "desc",
            description => "Descending"
        },
        {
            name        => "random",
            description => "Random"
        },
    ]
}

my %standard_fields = (
    -11 => '_id',
    -12 => '_version_datetime',
    -13 => '_version_user',
    -14 => '_deleted_by',
    -15 => '_created',
    -16 => '_serial',
);

sub _get_sorts
{   my $self = shift;

    my $_view = $self->_view or return [];

    # Sort order is defined by the database sequential ID of each sort
    my @sorts;
    foreach my $sort ($_view->sorts->all)
    {
        # XXX Convert from legacy internal IDs. This can be removed at some
        # point.
        my $layout_id = $sort->layout_id;
        if($layout_id && $layout_id < 0)
        {   my $layout = $self->layout;
            my $name = $standard_fields{$layout_id}
            my $col  = $name && $self->layout->column_by_name_short($name);
            $sort->update({ layout_id => $col->id }) if $col;
        }

        push @sorts, +{
            id        => $sort->id,
            type      => $sort->type,
            layout_id => $layout_id,
            parent_id => $sort->parent_id,
            filter_id => $sort->parent_id ? $sort->parent_id.'_'.$layout_id : $layout_id,
        };
    }
    \@sorts;
}

sub set_sorts
{   my $self = shift;
    $self->_set_sorts_groups('sorts', @_);
}

sub set_groups
{   my $self = shift;
    $self->clear_is_group;
    $self->_set_sorts_groups('groups', @_);
}

sub _set_sorts_groups
{   my ($self, $type, $sortfield, $sorttype) = @_;

    $type =~ /^(?:sorts|groups)$/
        or panic "Invalid sorts_groups type: $type";

    ref $sortfield eq 'ARRAY'
        or panic "Fields and types must be passed as ARRAY";

    $type ne 'sorts' || ref $sorttype eq 'ARRAY'
        or panic "Fields and types must be passed as ARRAY";

    my $table  = $type eq 'sorts' ? 'Sort' : 'ViewGroup';

    # Delete all old ones first
    $::db->delete($table => { view_id => $self->id });

    my @sorttype = $type eq 'sorts' && @$sorttype;
    my ($order, $type_last);
    my $layout = $self->layout;

    foreach my $filter_id (@$sortfield)
    {
        my ($parent_id, $column_id);
        ($parent_id, $column_id)
          = $filter_id && $filter_id =~ /^([0-9]+)_([0-9]+)$/
          ? ($1, $2)
          : (undef, $filter_id);

        my $sorttype = shift @sorttype || $type_last;
        error __x"Invalid type {type}", type => $sorttype
            if $type eq 'sorts'
            && ! grep $_->{name} eq $sorttype, @{$self->sort_types};

        # Check column is valid and user has access
        error __x"Invalid field ID {id} in {type}", id => $column_id, type => $type
            if $column_id && !$layout->column($column_id)->user_can('read');

        error __x"Invalid field ID {id} in {type}", id => $parent_id, type => $type
            if $parent_id && !$layout->column($parent_id)->user_can('read');

        my $sort = {
            view_id   => $self->id,
            layout_id => $column_id,
            parent_id => $parent_id,
            order     => ++$order,
        };
        $sort->{type} = $sorttype if $type eq 'sorts';
        $::db->create($table => $sort);
        $type_last = $sorttype;
    }
}

has is_group => (
    is      => 'lazy',
    isa     => Bool,
    builder => sub { !! @{$_[0]->groups },
);


=head2 my $page = $view->search(%options)
Apply the filters, and probably some temporary restrictions.  Returns
a L<Linkspace::Page>.

Options: C<page> (starting from 1), C<rows> max to return, C<from> DateTime.
=cut

sub search(%) { ... }


=head2 $view->filter_remove_column($column);
Remove the use of C<$column> from the filter.
=cut

sub filter_remove_column($)
{   my ($self, $column) = @_;
    my $stripped = $self->filter->remove_column($column);
    $self->filter($stripped);

    my $json     = encode_json $stripped;
    $self->update({filter => $json});
    $self->filter_json($json);
}

1;