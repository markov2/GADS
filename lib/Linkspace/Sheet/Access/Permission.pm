## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Sheet::Access::Permission;

use warnings;
use strict;

use Log::Report 'linkspace';
use Scalar::Util qw(blessed);

use Moo;
extends 'Linkspace::DB::Table';

=head1 NAME
Linkspace::Sheet::Access::Permission - one permission record for one group

=head1 SYNOPSIS

 my $access = $sheet->access;
 $access->group_allow($group, @permissions);
 $access->group_deny($group, @permissions);

=head1 DESCRIPTION
=cut

sub db_table { 'InstanceGroup' }

__PACKAGE__->db_accessors;

### 2020-08-17: columns in GADS::Schema::Result::InstanceGroup
# id          instance_id group_id    permission

sub path()
{   my $self = shift;
    $self->sheet->path . '/'.$self->group->name.'='.$self->permission;
}

# List also hard-coded in table.tt
my @sheet_permissions = qw/
    bulk_update
    create_child
    delete
    download
    layout
    link
    message
    purge
    view_create
    view_group
    view_limit_extra
/;

my %is_valid_permission = map +($_ => 1), @sheet_permissions;

sub _no_permission($$)
{   my ($class, $sheet, $group) = @_;
    $class->delete({
        instance_id => $sheet->id,
        group_id    => $group->id,
    });
}

sub _permission_create($)
{   my ($class, $insert) = @_;
    my $perm = $insert->{permission} or return;
    $is_valid_permission{$perm} or panic "Invalid allow permission $perm";
    $class->create($insert);
}

# No permission_update needed

has group => (
    is      => 'lazy',
    builder => sub { $::session->site->groups->group($_[0]->group_id) },
);

1;
