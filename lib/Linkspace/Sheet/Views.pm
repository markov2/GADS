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
    is      => 'lazy',
    builder => sub {
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

sub view_delete($)
{   my ($self, $which) = @_;
    my $view = $self->view($which) or return;

    #XXX move to ::View?
    my $view_ref = { view_id => $view_id };
    $::db->delete($_ => $view_ref)
        for qw/Filter ViewLimit ViewLayout Sort AlertCache Alert/;

    $view->delete;
}

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
        if ! $view->global
        && ! $view->is_limit_extra
        && ! $self->sheet->user_can('layout')
        && $view->owner->id == $user->id;

    return $view
        if $view->global
        && $view->group_id
        && $user->in_group($view->group_id);

    ();
}

=head2 my $view_id = $views->view_create(%insert);
=cut

sub view_create
{   my ($self, %insert) = @_;
    $::db->create(View => \%insert);
}

=head2 my $view = $views->view_temporary(%options);
Create a filters which is only temporary.
=cut

sub view_temporary(%)
{   my $self = shift;
    Linkspace::View->new(@_, sheet => $self->sheet);
}

#------------------------------
=head1 METHODS: ViewLimits
Relate view restrictions to users.

=head2 my @views = $views->limits_for_user($user);

=head2 my @views = $views->limits_for_user;

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
