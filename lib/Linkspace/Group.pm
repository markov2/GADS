## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Group;

use Log::Report 'linkspace';
use Scalar::Util qw/weaken/;
use Scalar::Util qw/blessed/;

use Linkspace::Util  qw/index_by_id/;
use Linkspace::Permission ();

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'Group' }

__PACKAGE__->db_accessors;

### 2020-03-17: columns in GADS::Schema::Result::Group
# id                                 default_read
# name                               default_write_existing
# site_id                            default_write_existing_no_approval
# default_approve_existing           default_write_new
# default_approve_new                default_write_new_no_approval

=head1 NAME
Linkspace::Group - groups of Users

=head1 DESCRIPTION
The term 'group' is used in few different contexts for different purposes, but
in most parts of the program it means 'group of Users'.

It is a bit inconvenient that the names of the columns do not match the
names of the permissions.  But prepending "default_" does more clearly
express what their effect is on the users in the group: setting overrulable
defaults.

=head1 METHODS: Constructors
=cut

sub _group_create($)
{   my ($class, $insert, %args) = @_;
    $class->create($insert, %args);
}

sub _group_update($)
{   my ($self, $insert) = @_;
    my $new_name = $insert->{name};
    info __x"Group {group.id} changed name from '{group.name}' into '{new_name}'",
        group => $self, new_name => $new_name
        if defined $new_name && $new_name ne $self->name;
    $self->update($insert);
}

sub _group_delete
{   my $self = shift;

    my $group_ref = { group_id => $self->id };
    $::db->delete($_ => $group_ref)
        for qw/LayoutGroup InstanceGroup UserGroup/;

    $self->delete;
}

sub path { my $self = shift; $self->site->path.'/'.$self->name }

#---------------
=head1 METHODS: Collection of users
Users are added and removed via C<<$site->users>> methods.
=cut

### 2020-05-04: columns in GADS::Schema::Result::UserGroup
# id         user_id    group_id

has _user_index => (
    is      => 'lazy',
    predicate => 1,
    builder => sub {
        my $self  = shift;
        my $users = $self->site->users;
        my $uids  = $::db->search(UserGroup => { group_id => $self->id })->get_column('user_id');
        my $index = index_by_id(map $users->user($_), $uids->all);
        weaken $_ for values %$index;
        $index;
    },
);

sub _add_user($)
{   my ($self, $user) = @_;
    $self->_user_index->{$user->id} = $user;
    weaken $self->_user_index->{$user->id};
    $::db->create(UserGroup => { group_id => $self->id, user_id => $user->id });
    $user;
}

sub _remove_user($)
{   my ($self, $user) = @_;
    $::db->delete(UserGroup => { group_id => $self->id, user_id => $user->id });
    delete $self->_user_index->{$user->id};
}

=head2 \@users = $group->users;
Returns the user (objects), link to this group sorted by 'value' (full name).
=cut

sub users() { [ sort { $a->value cmp $b->value } values %{$_[0]->_user_index} ] }

=head2 $group->has_user($which);
Returns true when the user is in the group.  The user can be specified as
object or id.
=cut

sub has_user($)
{   my ($self, $which) = @_;
    my $user_id = blessed $which ? $which->id : $which;
        $self->_has_user_index
      ? exists $self->_user_index->{$user_id}
      : defined $::db->get_record(UserGroup => { group_id => $self->id, user_id => $user_id });
}

#---------------
=head1 METHODS: Giving permission to sheets

=head2 \@shorts = $group->default_permissions;
=cut

sub default_permissions($)
{   my $data = $_[0]->_coldata;
    [ grep $data->{"default_$_"}, @{Linkspace::Permission->all_shorts} ];
}

=head2 \%table = $group->colid2perms;
Returns a HASH which contains all column_ids this group has explicit permissions
to, with an array of permission objects for that column. (Used in template C<group.tt>)
=cut

sub colid2perms()
{   my $self = shift;
    my $selected_rs = $::db->search(LayoutGroup => { group_id => $self->id });
    my (%perms, %perms_by_column);
    foreach my $sel ($selected_rs->next)
    {   push @{$perms_by_column{$sel->layout_id}}, $perms{$sel->permission} ||=
            Linkspace::Permission->new(short => $sel->permission);
    }
    \%perms_by_column;
}

1;
