package Linkspace::User::System;
use Moo;
extends 'Linkspace::User';

use warnings;
use strict;

use Log::Report 'linkspace';

use MooX::Types::MooseLike::Base qw/:all/;

=head1 NAME
Linkspace::User::Extern - someone via the web interface

=head1 SYNOPSIS

=head1 DESCRIPTION
These are the users which get a login via the web interface.  The existence
of these users is managed by L<Linkspace::Users>.

=head1 METHODS: Constructors

=head1 METHODS: Permissions

=cut

#XXX This is probably too easy.  Diffentiate between 'root' and other
#XXX system users?
sub is_admin { 1 }

=head1 METHODS: Groups
We ignore the existence of system groups (for now).

=head2 my @groups = $user->groups;
Returns an empty LIST.
=cut

sub groups { () }


1;
