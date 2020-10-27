## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::User;

use warnings;
use strict;

use Log::Report 'linkspace';
use Scalar::Util     qw/blessed/;
use DateTime::Format::CLDR ();

use Linkspace::Util  qw/is_valid_email/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

=head1 NAME
Linkspace::User - person or process accessing information

=head1 SYNOPSIS

=head1 DESCRIPTION
All actions performed with data are on request by a person or process: the
data B<user>, so the main component for this generic component is granting
permissions.

The following specific user groups are planned:

=over 4

=item L<Linkspace::User::Person>, someone via the web interface

=item L<Linkspace::User::System>, a process

=item C<Linkspace::User::REST>, for automated coupling (TBI)
XXX or is this a simple Person?

=back

=head1 METHODS: Constructors
=cut

sub _user_validate($)
{   my ($thing, $insert) = @_;

    ! defined $insert->{email} || is_valid_email $insert->{email}
        or error __"Invalid email address";

    ! $insert->{permissions} || $::session->user->is_admin
        or error __"You do not have permission to set the user's global permissions";
}

#------------------
=head1 METHODS: Permissions

=head2 is_admin
Returns true when the user has super user rights: can pass all checks.
=cut

# To be extended in sub-class
sub is_admin { 0 }

#-----------------
=head1 METHODS: Groups

=head2 my @groups = $user->groups;
=cut

#XXX Not sure whether this needs to be generic, but might simplify code.
sub groups { [] }

=head2 my $has = $user->is_in_group($which);
=cut

sub is_in_group($) { 0 }

#-----------------
=head1 METHODS: Other

=head2 my $can = $user->can_column($column, $action);
=cut

sub can_column($$)
{   my ($self, $column, $permission) = @_;
    1;
}

1;
