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

package Linkspace::Sheet::Views;

use Log::Report 'linkspace';
use Linkspace::Util qw/index_by_id/;

use Moo;
use MooX::Types::MooseLike::Base qw/ArrayRef HashRef Int Maybe Bool/;

has sheet => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

has _all_views_index => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub {
        my $sheet_id = $_[0]->sheet->id;
        index_by_id $::db->search(View => { instance_id => $sheet_id })->all;
    },
);

sub all_views() { [ map $_[0]->view($_), keys ${$_[0]->_all_views_index} ] } }

sub user_views(;$)
{   my ($self, $victim) = @_;
    $victim ||= $::session->user;

    my (@admins, @shared, @personal);
    foreach my $view ($self->all_views)
    {   my $set
          = $view->has_access_via_global($victim) ? \@shared
          : $user->is_admin ? \@admins
          :                   \@personal;
        push @$set, $view;
    }

      +{ admin => \@admins, shared => \@shared, personal => \@personal };
}

sub user_views_all(;$)
{   my $self = shift
    my $all  = $self->user_views(@_);
    [ @{$all->{shared}}, @{$all->{personal}}, @{$all->{admin}} ];
}

sub views_limit_extra() { [ grep $_->is_limit_extra, $_[0]->all_views ] }
sub view_default()      { $_[0]->user_views_all->[0] }

sub purge
{   my $self = shift;
    $self->view_delete($_) for @{$self->all_views};
}

=head2 my $view = $views->view($view_id, %options);
=cut

sub view($)
{   my ($self, $view_id, %args) = @_;
    defined $view_id or return;

    my $view  = first { $_->id == $view_id } @{$self->all_views}
        or return;

    Linkspace::View->from_record($view, sheet => $sheet)
        unless $view->isa('Linkspace::View');

    my $user  = $::session->user;

    return $view
        if $user->is_admin;

#XXX too many restrictions?
    return $view
        if $view->is_global && if $user->is_in_group($view->group_id);

    return $view
        if ! $view->is_limit_extra
        && ! $user->user_can('layout')
        && ($view->owner && $view->owner->id == $user->id);

    ();
}

=head2 my $view_id = $views->view_create($insert, %options);
Create a new View.
=cut

sub view_create
{   my ($self, $insert) = @_;

    my $view = Linkspace::View
        ->_view_validate($insert)
        ->_view_create($insert, sheet => $self->sheet);

    $self->_all_views_index->{$view->id} = $view if $self->_hash_all_views_index;
    $self->component_changed;
    $view;
}

=head2 $views->view_update($update, %options);
Change the view.
=cut

sub view_update($)
{
}

=head2 $views->trigger_alerts(%options);
Send alerts to everyone monitoring certains fields.  Requires are a C<current_ids> (the
records which have changed) and C<columns> (objects or ids which were updated).
=cut

sub trigger_alerts(%)
{   my ($self, %args) = @_;
#XXX
    my $alert_send = GADS::AlertSend->new(
        current_ids => \@changed,
        columns     => [ $self ],
    );
    $alert_send->process;
}

#------------------------------
=head1 METHODS: ViewLimits
Relate view restrictions to users.
=cut

### 2020-05-08: columns in GADS::Schema::Result::ViewLimit
# id         user_id    view_id

=head2 my @views = $views->limits_for_user($user?);
=cut

#XXX move to ::Person?  Used only once
sub limits_for_user(;$)
{   my $self = shift;
    my $user = shift || $::session->user;

    $::db->search(ViewLimit => { 'me.user_id' => $user->id })->all;
}

#------------------------------
=head1 METHODS: Other

=head2 $views->column_unuse($column);
Remove all uses for the column in this sheet (and managing objects);
=cut

sub column_unuse($)
{   my ($self, $column) = @_;
    my $col_id  = $column->id;

    $_->filters_remove_column($column)
        for @{$self->all_views};

    my $col_ref = { layout_id => $col_id };
    $::db->delete($_ => $col_ref)
        for qw/AlertCache AlertSend Filter Sort ViewLayout/;

    $::db->delete(Sort => { parent_id => $col_id });
    $self;
}

1;
