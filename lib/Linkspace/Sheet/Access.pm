package Linkspace::Sheet::Access;

use warnings;
use strict;

use Log::Report 'linkspace';
use Scalar::Util qw/blessed/;

use Linkspace::Sheet::Access::Permission;

=head1 NAME
Linkspace::Sheet::Access - manage the sheet's access

=head1 SYNOPSIS

  my $access = $sheet->access;

=head1 DESCRIPTION

=head1 METHODS: Constructors

=head1 METHODS: Other
=cut

# The index contains a HASH of permissions per (user)group_id.
has _permission_index => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my %perms = map +($_->group_id => $_->permission),
            Linkspace::Sheet::Access::Permission->search_objects(
               { sheet => $self->sheet }, sheet => $sheet);
        \%perms;
    },
);

=head2 my $perm = $access->group_permission($group, $permission);
Returns the L<Linkspace::Sheet::Access::Permission> object which represents the
record in the database.  Returns C<undef> if it does not exist.
=cut

sub group_permission($$)
{   my ($self, $group, $permission) = @_;
    my $group_id = blessed $group ? $group->id : defined $group ? $group : return;
    $self->_permission_index->{$group_id}{$permission};
}

=head2 $access->set_permissions(\@perms);
Change the Sheet wide permissions for groups.  There are also column specific permissions.

The C<@perms> are in the form C<< ${group_id}_${permission} >>, usually directly from
a web-form.
=cut

sub set_permissions
{   my ($self, $perms) = @_;
    my $index   = $self->_permission_index;
    my %missing = clone %$index;

    foreach my $perm (@perms)
    {   my ($group_id, $permission) = $perm =~ /^([0-9]+)\_(.*)/;
        delete $missing{$group_id}{$permission}
            or $self->group_allow($group_id, $permission);
    }

    foreach my $group_id (keys %missing)
    {   $self->group_deny($group_id, keys %{$missing{$group_id});
    }
}

=head2 $sheet->group_allow($group, @permissions);
=cut

sub group_allow($$)
{   my ($self, $group, @perms) = @_;
    my $group_id = blessed $group ? $group->id : defined $group ? $group : return;
    my $can      = $self->_permission_index->{$group_id};
    my @mine     = (sheet_id => $self->sheet_id, group_id => $group_id);

    Linkspace::Sheet::Access::Permission->_permission_create({ @mine, permission => $_ })
        for grep !$can->{$_}, @perms;
}

=head2 $sheet->group_deny($group, @permissions);
Without C<@permissions>, it removes all.
=cut

sub group_deny($$)
{   my ($self, $group, @perms) = @_;
    my $group_id = blessed $group ? $group->id : defined $group ? $group : return;
    my $can      = $self->_permission_index->{$group_id};

    if(!@perms) {
        Linkspace::Sheet::Access::Permission->_no_permission($self->sheet, $group);
        %$can = ();
        return;
    }

    foreach my $perm (@perms) {
        my $can = delete $can->{$perm} or next;
		$can->delete;
    }
}

=head2 $access->group_can($permission, $group);
=cut

sub group_can($$)
{   my ($self, $permission, $group) = @_;
    my $group_id = blessed $group ? $group->id : $group;
    $self->_permission_index->{$group_id}{$permission};
}

1;
