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

package GADS::Views;

use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/ArrayRef HashRef Int Maybe Bool/;

# Whether the logged-in user has the layout permission
has user_has_layout => (
    is      => 'lazy',
    builder => sub { $_[0]->layout->user_can("layout") },
);

# Whether to show another user's views
has other_user_id => (
    is  => 'ro',
    isa => Maybe[Int],
);

has sheet => (
    is       => 'ro',
    isa      => InstanceOf['Linkspace::Sheet'],
    required => 1,
    weakref  => 1,
);

has user_views => (
    is      => 'rw',
    lazy    => 1,
    isa     => HashRef,
);

has user_views_all => (
    is  => 'lazy',
    isa => ArrayRef,
    builder => sub {
        my $all = shift->user_views;
        [ @{$all->{shared}}, @{$all->{personal}}, @{$all->{admin}} ];
    },
}

has global_view_ids => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub {
        my $self = shift;
        my $views = $::db->search(View => {
            global      => 1,
            instance_id => $self->instance_id,
        });
        [ map $self->view($_->id), $views->all ];
    },
);

has all => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub {
        my $self  = shift;
        my $views = $::db->search(View => { instance_id => $self->sheet->id });
        [ map $self->view($_->id), $views->all ];
    },
);

sub builder_user_views
{   my $self = shift;

    # Allow user ID to be overridden, but only if the logged-in user has permission
    my $user_id = ($self->user_has_layout && $self->other_user_id)
       || ($self->layout->user && $self->layout->user->id);

    my @search = (
        'me.user_id' => $user_id,
        {
            global  => 1,
            -or     => [
                'me.group_id'         => undef,
                'user_groups.user_id' => $user_id,
            ],
        }
    );

    push @search, (is_admin => 1)
        if $self->user_has_layout;

    my @views = $::db->search(View => {
        -or         => \@search,
        instance_id => $self->instance_id,
    },{
        join     => {
            group => 'user_groups',
        },
        order_by => ['me.global', 'me.is_admin', 'me.name'],
        collapse => 1,
    })->all;

    my (@admins, @shared, @personal);
    foreach my $view (@views)
    {   push @{ $view->global   ? \@shared
              : $view->is_admin ? \@admins
              :                   \@personal}, @view;
    }

      +{ admin => \@admins, shared => \@shared, personal => \@personal };
}

has views_limit_extra => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        return [] if !$self->sheet->user_can('view_limit_extra');

        my $views = $::db->search(View =>
            is_limit_extra => 1,
            instance_id    => $self->sheet->id,
        },{
            order_by => 'me.name',
        });
        [ $views->all ];
    },
);

# Default user view
#XXX rename to default_view
sub default
{   my $self = shift;
    my $default_view = $self->user_views_all->[0] or return;
    my $view_id      = $default_view->id or return;
    $self->view($view_id);
}

sub purge
{   my $self = shift;
    foreach my $view (@{$self->all})
    {   $::db->delete(ViewLimit => { view_id => $view->id });
        $view->delete;
    }
}

=head2 my $view = $views->view($view_id, %options);
=cut

sub view($)
{   my ($self, $view_id, %args) = @_;
    my $sheet = $self->sheet;

    my $view = Linkspace::View->from_id($view_id,
        sheet => $sheet,
    ) or return;

    return $view if $self->user_permission_override;

    my $user  = $::session->user;
    my $owner = $view->owner;

    return 1
        if !$view->global
        && !$view->is_admin
        && !$view->is_limit_extra
        && !$view->user_can_layout
        && $owner->id==$user->id;

    return 1
        if $view->global
        && $view->group_id
        && $user->has_group($view->group_id);

    return 1
        if $user->is_admin;

    0;
}

=head2 my $view_id = $views->create_view(%data);

=head2 my $view_id = $views->create_view(\%data, %options);
=cut

sub create_view
{   my $self = shift;
    my ($data, $args) = @_%1 ? (shift, +{@_}) : (+{@_}, {});

    Linkspace::View->create($data, 
}

1;
