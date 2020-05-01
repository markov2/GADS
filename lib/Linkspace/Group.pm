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

package Linkspace::Group;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'Linkspace::DB::Table';

sub db_table { 'Group' }

sub db_rename {
    +{ map +($_ => "default_$_"), GADS::Type::Permissions->all_shorts };
}

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

=head1 METHODS: Other

=head2 \%table = $groups->colid2perms;
Returns a HASH which contains all column_ids this group has explicit permissions
to, with an array of permission objects for that column. (Used in template C<group.tt>)
=cut

sub colid2perms()
{   my $self = shift;
    my @selected = $::db->search(LayoutGroup => { group_id => $self->id })->all;
    my %columns;
    foreach my $selected (@selected)
    {   push @{$columns{$selected->layout_id}},
            GADS::Type::Permission->new(short => $selected->permission);
    }
    \%columns;
}

1;


