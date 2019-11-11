package Linkspace::User;

use warnings;
use strict;

use Log::Report 'linkspace';

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

=item C<Linkspace::User::Test>, used for test scripts (TBI)

=item C<Linkspace::User::REST>, for automated coupling (TBI)

=cut

=head1 METHODS: Constructors

=head1 METHODS: Permissions

=head2 is_admin
Returns true when the user has super user rights: can pass all checks.
=cut

# To be extended in sub-class
sub is_admin { 0 }


=head1 METHODS: Groups

=head2 my @groups = $user->groups;
=cut

#XXX Not sure whether this needs to be generic, but might simplify code.
sub groups { () }

1;
