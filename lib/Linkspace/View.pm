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
use List::Util qw(first);

#use Linkspace::View::Alert;
#use Linkspace::View::Filter;
#use Linkspace::View::Sorting;
#use Linkspace::View::Grouping;
use Linkspace::Util qw/flat/;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'Linkspace::DB::Table';

sub db_table { 'View' }

sub db_field_rename { +{
    filter   => 'filter_json',
    global   => 'is_global',
    user_id  => 'owner_id',
    is_admin => 'is_for_admins',  # for sheet admins
} };

### 2020-04-16: columns in GADS::Schema::Result::View
# id             user_id        group_id
# instance_id    filter         is_admin
# name           global         is_limit_extra

use namespace::clean;

=head1 NAME

Linkspace::View - rules to sub-set sheet data

=head1 SYNOPSIS

=head1 DESCRIPTION
A user's View restricts the data in a sheet according to rules.  Applying
the view on the data results in a Page.

The View does not only restrict the data you can see via a Filter, but
also defines Sorting and Grouping on the (temporary) results.  When values
in the View change, it may trigger Alerts.

A user's view on sheet data can be limited by a View, which is in the ViewLimit
table, which is managed by L<Linkspace::Site::Users>.

=head1 METHODS: constructors

=cut

sub _view_validate($)
{   my ($thing, $changes) = @_;

    if(exists $changes->{is_global})
    {   my $owner = delete $changes->{owner} || delete $changes->{owner_id};
        unless($changes->{is_global})
        {   my $user  = $::session->user;
            my $owner_id = blessed $owner ? $owner->id : $owner;
            $user->is_admin || $owner_id==$user->id
                or error __x"You cannot create a view for someone else";
            $changes->{owner} = $owner;
        }
    }

    # XXX Database schema currently restricts length of name. Should be changed
    # to normal text field at some point
    exists $changes->{name} && length $changes->{name} < 128
        or error __"View name must be less than 128 characters";

    if(   (exists $changes->{is_global} && $changes->{is_global})
       || (exists $changes->{is_for_admins} && $changes->{is_for_admins} ))
    {   # Refuse owner
        $changes->{user_id} = undef;
        delete $changes->{user};
    }

    if(my $filter = Linkspace::Filter->from_json($changes->{filter_json}))
    {   $filter->_filter_validate($thing);
        $changes->{filter} = $filter;
    }

    $thing;
}

sub _view_create
{   my ($class, $insert, %args) = @_;
    $insert->{name} or error __"Please enter a name for the view";

    my $sheet   = $args{sheet} or panic;
    my $col_ids = [ flat delete $insert->{column_ids} ];

    $insert->{is_global}     ||= 0;
    $insert->{is_for_admins} ||= 0;
    $insert->{is_global}       = ! $insert->{owner};

    my @relations = (
        sortings  => delete $insert->{sortings},
        groupings => delete $insert->{groupings},
        monitor   => delete $insert->{columns},
    );

    $class->_view_validate($insert);
    my $self = $class->create($insert, %args);

    my $user    = $::session->user;
    unless($self->is_writable($user))
    {   #XXX We need the object to check for write rights :-(  Maybe simplifications in
        #    in that logic can avoid that.
       $self->_view_delete;   # erase it immediately
        error __x"User {user.path} does not have permission to create new views", user => $user;
    }

    $self->_update_relations(@relations);
    $self->filter_changed;
    $self;
}

sub _view_update
{   my ($self, $update, %args) = @_;
    my $user = $::session->user;

    # Preserve owner if editing other user's view
    if(! $self->owner && ! $update->{owner_id} && ! $update->{owner})
    {   $update->{owner} = $user if $self->sheet->is_writable($user);
    }

    $self->is_writable($user)
        or error __x"User {user.path} does not have permission to create new views", user => $user;

    my @relations = (
        sortings  => delete $update->{sortings},
        groupings => delete $update->{groupings},
        monitor   => delete $update->{columns},
    );

    $self->_view_validate($update)->update(View => $self->id, $update);

    $self->_update_relations(@relations);
    $self->filter_changed if $update->{filter_json} || $update->{filter};
    $self;
}

sub _view_delete
{   my $self = shift;
    $self->_update_relations(sortings => [], groupings => [], monitor => []);
##  $self->alert->_alert_delete($self);
    $self->site->users->view_unuse($self);
    $self->filter->view_unuse($self); #XXX
    $self->delete;
}

sub _update_relations(%)
{   my ($self, %rels) = @_;
    $self->_set_monitor($rels{monitor});
    $self->_set_sortings($rels{sortings});
    $self->_set_groupings($rels{groupings});
}

#---------------
=head1 METHODS: Attributes

=head2 my $user  = $view->owner;
=head2 my $group = $view->group;
=cut

sub owner { $_[0]->site->users->user($_[0]->owner_id) }
sub group { $_[0]->site->groups->group($_[0]->group_id) }

sub has_access_via_global($)
{   my ($self, $victim) = @_;
    $self->is_global or return 0;

    my $group = $self->group;
    $group && $group->has_user($victim);
}

=head2 $view->is_writable($user?)
Returns true when the C<$user> has write rights on the view.  There are a
few ways to get these rights, which are documented here: XXX
=cut

sub is_writable(;$)
{   my ($self, $victim) = @_;
    my $sheet = $self->sheet;

    $victim ||= $::session->user;
    return $sheet->is_writable($victim)
        if $self->is_for_admins;

    if($self->is_global)
    {   return $self->group_id
          ? $self->group_id && $sheet->user_can(view_group => $victim)
          : $sheet->is_writable($victim);
    }

    return 1 if $sheet->user_can(view_create => $victim)
             || ($self->owner_id //0) == $victim->id;

    $sheet->is_writable($victim);
}

#---------------
=head1 METHODS: Grouping columns
Implements a kind of "group by" function from SQL: reduce based on column
equal values.
=cut

### Object definitions below

has _view_groupings => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        Linkspace::View::Grouping->search_objects({ view => $self }, view => $self);
    },
);

sub groupings { [ sort {$a->order <=> $b->order} $_[0]->_view_groupings ] }
sub grouping_column_ids { [ grep $_->column_id, @{$_[0]->groupings} ] }
sub does_column_grouping { !! keys %{$_[0]->_view_groupings} }

sub grouping_on($)
{   my ($self, $which) = @_;
    my $col_id = blessed $which ? $which->id : defined $which ? $which : return 0;
    $self->_view_groupings->{$col_id};
}

#XXX???
# The current field that is being grouped by in the table view, where a view
# has more than one group and they can be drilled down into

sub first_grouping_column_id()
{    my $groups = shift->groupings;
     @$groups ? $groups->[0]->layout_id : undef;
}

sub _set_groupings
{   my ($self, $filter_ids) = @_;

    my (@groupings, $order);
    foreach my $filter_id (@$filter_ids)
    {   my ($parent_id, $column_id) = $self->_unpack_filter_id(groupings => $filter_id);
        push @groupings, +{
            column_id => $column_id,
            parent_id => $parent_id,
            order     => ++$order,
        };
    }

    Linkspace::View::Groupings->set_record_list
      ( { view => $self }, \@groupings, \&_filter_rec_uniq );
}

#---------------
=head1 METHODS: Manage Alerts

=head2 \@alerts = $view->all_alerts;
=head2 $has = $view->has_alerts;
=cut

has _alerts => (
    is      => 'lazy',
    builder => sub { Linkspace::View::Alert->search_objects({view => $_[0]}) },
);

sub all_alerts { $_[0]->_alerts }
sub has_alerts { scalar @{$_[0]->_alerts} }

=head2 my $alert = $view->alert_for($user?);
Returns the single alert object for the user.
=cut

#XXX is there only one?   Warning: alerts() is a Perl built-in
sub alert_for($)
{   my ($self, $which) = @_;
    $which ||= $::session->user;
    my $user_id = blessed $which ? $which->id : $which;
    first { $user_id == $_->id } @{$self->_alerts};
}

=head2 $view->alert_set($frequency, $user?);
Insert or update an alert for the C<$user>.  When the C<$frequency> is false,
the alert gets removed.
=cut

sub alert_set($;$)
{   my ($self, $frequency, $user) = @_;
    $user ||= $::session->user;
    my $all = $self->_alerts; 

    my $user_id = $user->id;
    if(my $alert = first { $user_id == $_->id } @$all)
    {   if(defined $frequency)
        {   $alert->_alert_update({frequency => $frequency});
        }
        else
        {   $alert->_alert_delete($self);
            @$all = grep $_->owner_id != $user->id, @$all;
        }
    }
    elsif(defined $frequency)
    {   my $alert = Linkspace::View::Alert->_alert_create({
             view => $self, owner => $user, frequency => $frequency
        });

        # Check whether this view already has alerts. No need for another
        # cache if so, unless view filtter contains CURUSER
        $self->update_cache if ! @$all || $self->has_curuser;
        push @$all, $alert;
    }
}

=head2 \@cached = $view->alerts_cached_for($column)
Most "cached" information is handled in "Alerts", but the reverse lookup (to
be abled to see whether the column is triggering any alert) is global on the
view for reasons of performance.
=cut

sub alerts_cached_for($)
{   my ($self, $column) = @_;
    Linkspace::View::Alert->cached_for($column);
}

=head2 \%h = $view->alerts_for_user($user?);
Returns a nested HASH with as key the view-ids, and the alert info
as HASH as value, to be used in the web-interface.

We do not have the View objects, so does not return full Alert objects
(for the moment).
=cut

#XXX where was the original code used?
sub alerts_for_user(;$)
{   my ($self, $victim) = @_;
    $victim ||= $::session->user;
    my $cols = Linkspace::View::Alert->search_records({ user => $victim });
      +{ map +($_->view_id => $_), @$cols };
}

=head2 \@user_ids = $view->alert_users_ids;
Finds all user-ids for users which have an alert on this view.  When the
filter does not produce different results per user, this will return
undef.
=cut

sub alert_users_ids()
{   my $self = shift;
    return unless $self->filter->depends_on_user;
    my $alerts = Linkspace::View::Alert->search_records({ view => $self });
    [ map +($_->user_id), @$alerts ];
}

#--------------
=head1 METHODS: Manage Columns which are monitored
=cut

sub monitors_on_column($)
{   my ($self, $column) = @_;
    # ViewLayout ($view, $column)
}


sub _set_monitor($)
{   my ($self, $col_ids) = @_;
    defined $col_ids or return;

    $self->column_monitor->_columns_update;

    my %colviews = map +($_ => 1), @{$self->column_ids};

### 2020-05-10: columns in GADS::Schema::Result::ViewLayout
# id         layout_id  order      view_id
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    foreach my $column (grep $colviews{$_->id}, @$columns)
    {
        # Column should be in view
### next if $view->monitors_column($column);

        my %item = (view_id => $self->id, layout_id => $column->id);
        next if $::db->get_record(ViewLayout => \%item)->count;

### Linkspace::View::Column->_column_create(\%item);
        $::db->create(ViewLayout => \%item);

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
}

sub view_delete()
{   my ($self) = @_;

    $self->is_writable
        or error __x"You do not have permission to delete {id}", id => $self->id;

    my $view_limits = $self->all_view_limits;
    if(@$view_limits)
    {   my $users = join '; ', map $_->user->fullname, @$view_limits;
        error __x"This view cannot be deleted as it is used to limit user data. Remove the view from the limited views of the following users before deleting: {users}", users => $users;
    }

    my $ref_view = { view_id => $self->id };
    $::db->delete($_ => $ref_view)
        for qw/Sort ViewLayout ViewGroup Filter AlertCache/;

    $_->alert_delete for $self->all_alerts;
    # $self->filter_changed;

    $::session->site->users->view_unuse($self);
    $self->delete;
}

#----------------
=head1 METHODS: Sorting

=head2 \@info = $thing->sort_types;
=cut

### 2020-05-08: columns in GADS::Schema::Result::Sort
# id         type       layout_id  order      parent_id  view_id
#WARNING: no ::DB::Table smart field translations.

has _sorts => (
    is => 'lazy',
    builder => sub { Linkspace::View::Sorting->search_records({view => $_[0]}) },
);

sub show_sorts
{   my $self = shift;

    # Sort order is defined by the database sequential ID of each sort
    #XXX there is an 'order' field in the table

    [ map $_->info, sort { $a->id <=> $b->id } @{$self->all_sorts} ];
}

sub _unpack_filter_id($$)
{   my ($self, $type, $filter_id) = @_;

    my ($parent_id, $column_id)
     = $filter_id && $filter_id =~ /^([0-9]+)_([0-9]+)$/
     ? ($1, $2)
     : (undef, $filter_id);

    error __x"Invalid field ID {id} in {type}", id => $column_id, type => $type
        if $column_id && !$self->column($column_id)->user_can('read');

    error __x"Invalid field ID {id} in {type}", id => $parent_id, type => $type
        if $parent_id && !$self->column($parent_id)->user_can('read');

    ($parent_id, $column_id);
}

sub _filter_rec_uniq { $_[0]->layout_id . '\0' . ($_[0]->parent_id // '\0') }

sub _set_sortings
{   my ($self, $sortings) = @_;
    my $order = 0;

    my @sortings;
    foreach (@$sortings)
    {   my ($filter_id, $sort_type) = @$_;
        my ($parent_id, $column_id) = $self->_unpack_filter_id(sortings => $filter_id);
        push @sortings, +{
            column_id => $column_id,
            parent_id => $parent_id,
            type      => $sort_type,
            order     => ++$order,
        };
    }

    Linkspace::View::Sortings->set_record_list
      ( { view => $self }, \@sortings, \&_filter_rec_uniq );
}


=head2 my $page = $view->search(%options)
Apply the filters, and probably some temporary restrictions.  Returns
a L<Linkspace::Page>.

Options: C<page> (starting from 1), C<rows> max to return, C<from> DateTime.
=cut

sub search(%) { ... }


#--------------
=head1 METHODS: Manage Filter
This used the L<Linkspace::View::Filter> object, which extends a generic
L<Linkspace::Filter>>

=head2 my $filter = $view->filter;
=cut

has filter => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        Linkspace::View::Filter->from_json($self->filter_json, view => $self);
    },
);

=head2 $view->filter_remove_column($column);
Remove the use of C<$column> from the filter.
=cut

sub filter_remove_column($)
{   my ($self, $column) = @_;
    my $stripped = $self->filter->remove_column($column);
    $self->filter($stripped);
    $self->update({filter_json => $stripped});
}

=head2 $view->filter_changed;
Call which when the filter value has changed: this may require updates in the
alert cache and in the Filter table.
=cut

sub filter_changed()
{   my $self = shift;

    # Update any alert caches for new filter
    if($self->has_alerts)
    {   my $alert = $self->alert_create({}); #XXX
        $alert->update_cache;
    }

    if(my $filter = $self->filter)
    {   $filter->columns_update;
    }
    else
    {   Linkspace::View::Filter->unuse_view($self);
    }

}

1;
