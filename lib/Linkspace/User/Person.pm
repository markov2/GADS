package Linkspace::User::Person;

use Moo;
extends 'Linkspace::User', 'GADS::Schema::Result::User';

use warnings;
use strict;

use Log::Report 'linkspace';

use MooX::Types::MooseLike::Base qw/:all/;

=head1 NAME
Linkspace::User::Person - someone via the web interface

=head1 SYNOPSIS

=head1 DESCRIPTION
These are the users which get a login via the web interface.  The existence
of these users is managed by L<Linkspace::Users>.

=head1 METHODS: Constructors

=head2 my $user = $class->from_data(\%data);
Upgrades a raw database record of type L<GADS::Schema::Result::User> into
a qualified Linkspace user (by blessing).
=cut

sub from_data
{   my ($class, $data) = @_;

    #XXX Probably more work to do here, later
    bless $data, $class;
}

=head1 METHODS: Permissions

=cut

sub is_admin { $_[0]->permissions->{superadmin} }

=head1 METHODS: Groups

=head2 my @group_names = $user->groups_viewable;
Groups that this user should be able to see for the purposes of things like
creating shared graphs.
=cut

sub groups_viewable
{   my $self = shift;

    my $site = $::session->site;

    return $site->resultset('Group')->all
        if $self->is_admin;

    # Layout admin, all groups in their layout(s)
    my $instance_ids = $site->search(InstanceGroup => {
        'me.permission'       => 'layout',
        'user_groups.user_id' => $self->id,
    },{
        join => {
            group => 'user_groups',
        },
    })->get_column('me.instance_id');

    my $owner_groups = $site->search(LayoutGroup => {
        instance_id => { -in => $instance_ids->as_query },
    }, {
        join => 'layout',
    });

    my %groups = map +($_->group_id => $_->group),
        $owner_groups->all, $self->user_groups;

    values %groups;
}


=head2 my @groups = $user->groups;
=cut

sub groups { map $_->group, $_[0]->user_groups }

=head2 $user->set_groups(\@group_ids);
=cut

sub set_groups
{   my ($self, $group_ids) = @_;
    my $has_group = $self->has_group;
    my $is_admin  = $self->is_admin;

    foreach my $g (@$group_ids)
    {   next if $is_admin || $has_group->{$g};
        $self->find_or_create_related(user_groups => { group_id => $g });
    }

    # Delete any groups that no longer exist
    my @has_group_ids = map $_->id,
        grep $is_admin || $has_group->{$_->id},
            $::session->site->resultset('Group')->all;

    #XXX this is too complex
    my %search;
    $search{group_id} = { '!=' => [ -and => @$group_ids ] } if @$group_ids;
    $self->search_related(user_groups => \%search)
        ->search({ group_id => \@has_group_ids })
        ->delete;
}


=head1 METHODS: Views

=head2 $user->view_limits_with_blank
Used to ensure an empty selector is available in the user edit page.
=cut

sub view_limits_with_blank
{   my $view_limits = shift->view_limits;
    $view_limits->count ? $view_limits : [ undef ];
}

=head2 $user->set_view_limits(\@view_ids);

=head2 $user->set_view_limits(\@views);
=cut

sub set_view_limits
{   my ($self, $views) = @_;
    my @view_ids = map +(ref $_ ? $_->id : $_), $views;

    $self->find_or_create_related(view_limits => { view_id => $_ })
        for @view_ids;

    # Delete any groups that no longer exist
    my %search;
    $search{view_id} = { '!=' => [ -and => @view_ids ] }
        if @view_ids;

    $self->search_related(view_limits => \%search)->delete;
}


=head1 METHODS: Graphs

=head2 $user->set_graphs($instance, \@graph_ids);
=cut

sub set_graphs
{   my ($self, $instance, $graph_ids) = @_;
    my $instance_id = ref $instance ? $instance->id : $instance;

    foreach my $g (@$graph_ids)
    {
        $self->search_related(user_graphs => { graph_id => $g })->count
            or $self->create_related(user_graphs => { graph_id => $g });
    }

    # Delete any graphs that no longer exist
    my %search = ( 'graph.instance_id' => $instance_id );
    $search{graph_id} = { '!=' => [ -and => @$graph_ids ] } if @$graph_ids;

    $self->search_related(user_graphs => \%search, { join => 'graph' })->delete;
}

1;
