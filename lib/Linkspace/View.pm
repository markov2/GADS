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
    filter  => 'filter_json',
    global  => 'is_global',
    user_id => 'owner_id',
} };

### 2020-04-16: columns in GADS::Schema::Result::View
# id             user_id        group_id
# instance_id    filter         is_admin
# name           global         is_limit_extra

# $view->is_admin means that only $sheet->owner can see it

use namespace::clean;

=head1 NAME

Linkspace::View - rules to sub-set sheet data.

=head1 SYNOPSIS

=head1 DESCRIPTION
A user's View restricts the data in a sheet according to rules.  Applying
the view on the data results in a Page.

=head1 METHODS: constructors

=cut

sub _view_validate($)
{   my ($thing, $changes) = @_;

    if(exists $changes->{is_global})
    {   if($changes->{is_global})
        {   delete $changes->{owner};
            delete $changes->{owner_id};
        }
        else
        {   my $user = $::session->user;
            $changes->{owner} ||= $user unless $changes->{owner_id};
            $user->is_admin || ($changes->{owner_id} || $changes->{owner}->id)==$user->id
                 or error __x"You cannot create a view for someone else";
        }
    }

    $thing;
}

sub _view_create($%)
{   my ($class, $insert, %args) = @_;

    my @relations = ...
    my $self  = $class->create($insert, %args);
    $self->_update_relations(@relations);
}

sub _view_delete
{   my $self = shift;
    my $view_ref = { view_id => $self->id };
    $::db->delete($_ => $view_ref)
        for qw/Filter ViewGroup ViewLimit ViewLayout Sort AlertCache Alert/;

    $self->delete;
}

#---------------
=head1 METHODS: Attributes

=head2 my $user = $view->owner;
=cut

has owner => (
    is      => 'lazy',
    weakref => 1,
    builder => sub { $_[0]->site->users->user($_[0]->owner_id) },
);

has filter => (
    is      => 'lazy',
    builder => sub { Linkspace::Filter->from_json($_[0]->filter_json) },
);

#---------------
=head1 METHODS: Grouping columns
Implements a kind of "group by" function from SQL: reduce based on column
equal values.
=cut

### Object definitions below

has _view_groups => (
    is      => 'lazy',
    builder => sub {
        Linkspace::View::Grouping->search_objects({ view => $self }, view => $self);
    },
);

sub groupings { [ sort {$a->order <=> $b->order} $_[0]->_view_groups ] }
sub grouping_column_ids { [ grep $_->layout_id, @{$_[0]->groupings} ] }

#XXX is_grouped?  has_groups?  is_grouped_view?  does_column_grouping?
sub is_group { !! keys %{$_[0]->_view_groups} }

#XXX???
# The current field that is being grouped by in the table view, where a view
# has more than one group and they can be drilled down into

sub first_grouping_column_id()
{    my $groups = $self->groupings;
     @$groups ? $groups->[0]->layout_id : undef;
}

#---------------
=head1 METHODS: Manage Alerts

=head2 my $alert = $view->alert($user?);
Returns the single alert object for the user.
=cut

sub alert
{   my ($self, $which) = @_;
    $which ||= $::session->user;
    my $user_id = blessed $which ? $which->id : $which;
    first { $user_id == $_->id } @{$self->_alerts};
);

=head2 $has = $view->has_alerts;
=cut

has _alerts => (
);

sub has_alerts { scalar @{$_[0]->_alerts} }

#--------------
=head2 METHODS: Manage Columns
=cut

sub column_ids { [ map $_->column_id, @{$self->view_columns} ] }

#--------------
=head2 METHODS: Manage CURUSER
=cut

# Whether the view has a variable "CURUSER" condition
sub has_curuser { my $f = $_[0]->filter; $f && $f->has_curuser }


sub has_access_via_global($)
{   my ($self, $victim) = @_;
    my $gid = $self->group_id;
    $gid && $self->is_global ? $victim->is_in_group($gid) : 0;
}

sub _is_writable($;$)
{   my ($self, $sheet, $victim) = @_;
    $victim ||= $::session->user;
    my $owner_id = $self->user_id;

#XXX this is a bit weird... usually, the ways to get access work
#XXX in parallel

    if($self->is_admin)
    {   return 1 if $sheet->user_can(layout => $victim);
    }
    elsif($self->is_global)
    {   return 1 if !$self->group_id && $sheet->user_can(layout => $victim);
        return 1 if  $self->group_id && $sheet->user_can(view_group => $victim);
    }
    elsif($owner_id && $owner_id == $victim->id)
    {   return 1 if $sheet->user_can(view_create => $victim);
    }
    else
    {   return 1 if $sheet->user_can(layout => $victim);
    }

    0;
}

sub _sorts($$)
{    my ($self, $fields, $types) = @_;
#TODO move code from write() here
}

sub _view_validate($)
{   my ($thing, $changes) = @_;

    # XXX Database schema currently restricts length of name. Should be changed
    # to normal text field at some point
    exists $changes->{name} && length $changes->{name} < 128
        or error __"View name must be less than 128 characters";


    my $col_ids = delete $update{column_ids} || [];
    $col_ids    = [ $col_ids ] if ref $col_ids eq 'ARRAY';

    if(   (exists $changed->{is_global} && $changed->{is_global})
       || (exists $changed->{is_admin}  && $changed->{is_admin} ))
    {   # Refuse owner
        $changes->{user_id} = undef;
        delete $changes->{user};
    }

    if(my $filter = Linkspace::Filter->from_json($changes->{filter}))
    {   $filter->_filter_validate($layout);
        $changes->{filter} = $filter;
    }
}

sub _view_create
{   my ($class, $insert, %args) = @_;
    $insert->{name} or error __"Please enter a name for the view";

    $insert->{is_global} = 0 unless exists $insert->{is_global};
    $insert->{is_admin}  = 0 unless exists $insert->{is_admin};
    $insert->{owner}   ||= $::session->user unless $insert->{owner_id};
    $class->_view_validate($insert);
    $insert->{is_global} = !$insert->{owner} && !$insert->{owner_id};

    $class->create($insert, %args);
}

sub _view_update
{   my ($self, $update, %args) = @_;

    # Preserve owner if editing other user's view
    if(! $self->owner && ! $update->{owner_id} && ! $update->{owner})
    {   my $user = $::session->user;
        $update->{owner} = $user if $sheet->user_can(layout => $user);
    }

    $self->_view_validate($insert);

    $self->_update_column_ids($col_ids);
    $self->_set_sorts(delete $update{sortfields}, $update{sorttypes});
    $self->_set_groupings(delete $update{groups});

    $self->update(View => $self->id, \%update);

    # Update any alert caches for new filter
    if($update{filter}  && $self->has_alerts)
    {   my $alert = $self->alert_create({}); #XXX
        $alert->update_cache;
    }
}

sub write
{   my ($self, $sheet, %options) = @_;

    my $fatal = $options{no_errors} ? 0 : 1;

    my $user = $::session->user;
    $self->writable($sheet)
        or error $self->id
            ? __x("User {user_id} does not have access to modify view {id}", user_id => $user->id, id => $self->id)
            : __x("User {user_id} does not have permission to create new views", user_id => $user->id);

    my %colviews = map +($_ => 1), @{$self->column_ids};

### 2020-05-10: columns in GADS::Schema::Result::ViewLayout
# id         layout_id  order      view_id
    my $columns = $sheet->layout->columns_search(user_can_read => 1);
    foreach my $column (grep $colviews{$_->id}, @$columns)
    {
        # Column should be in view
### next if $view->column_monitor($column);

        my %item = (view_id => $self->id, layout_id => $column->id);
        next if $::db->get_record(ViewLayout => \%item)->count;

### my $monitor = $view->column_monitor_create($column, $order?, view => $view);
        $::db->create(ViewLayout => $item);

#XXX The next block is:  (move to Alerts class)
#XXX $self->alert_cache_create({column => $column, current_id => $_->current_id})
#XXX   for $alert->alert_caches;

        # Update alert cache with new column
# $view->all_alerts
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
                layout_id  => $column->id,
                view_id    => $self->id,
                current_id => $_->current_id,
            }, $alert->alert_caches;
        }
        $::db->resultset('AlertCache')->populate(\@pop) if @pop;
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

    $users->view_unuse($view);
    $view->delete;
}

#----------------
=head1 METHODS: Sorting

=head2 \@info = $thing->sort_types;
=cut

### 2020-05-08: columns in GADS::Schema::Result::Sort
# id         type       layout_id  order      parent_id  view_id
#WARNING: no ::DB::Table smart field translations.

sub sort_types
{   [ { name => 'asc',    description => 'Ascending' },
      { name => 'desc',   description => 'Descending' },
      { name => 'random', description => 'Random' },
    ]
}

has sorts => (
    is      => 'lazy',
);

my %standard_fields = (
    -11 => '_id',
    -12 => '_version_datetime',
    -13 => '_version_user',
    -14 => '_deleted_by',
    -15 => '_created',
    -16 => '_serial',
);

sub _build_sorts
{   my $self = shift;

    # Sort order is defined by the database sequential ID of each sort
    #XXX
    my $sorts_rs = $::db->search(Sort => {view_id => $self->id},
      {order_by => 'id'} );

    my @sorts;
    while(my $sort = $sorts_rs->next)
    {
        #XXX Convert from legacy internal IDs. This can be removed at
        # some point.  XXX convert to database update script.
        my $col_id = $sort->layout_id;
        if($col_id && $col_id < 0)
        {   my $new_col = $self->column($standard_fields{$col_id});
            $sort->update({ layout_id => $new_col->id }) if $new_col;
        }

        my $pid = $sort->parent_id;
        push @sorts, +{
            id        => $sort->id,
            type      => $sort->type,
            column_id => $col_id,
            parent_id => $pid
            filter_id => $pid ? "${pid}_${col_id}" : $col_id,
        };
    }
    \@sorts;
}

sub set_sorts
{   my $self = shift;
    $self->_set_sorts_groups(sorts => @_);
}

sub set_groups
{   my $self = shift;
    $self->_set_sorts_groups(groups => @_);
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

#====================================
package Linkspace::View::Grouping;

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'ViewGroup' }

### 2020-05-09: columns in GADS::Schema::Result::ViewGroup
# id         layout_id  order      parent_id  view_id

has view => (
    is       => 'ro',
    weakref  => 1,
    required => 1,
);

sub path() { $_[0]->view->path . '/' . $_[0]->SUPER::column($_[0]->short_name) }

1;
