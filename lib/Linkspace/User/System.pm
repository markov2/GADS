package Linkspace::User::System;
use Moo;
extends 'Linkspace::User';

use warnings;
use strict;

use Log::Report 'linkspace';

use MooX::Types::MooseLike::Base qw/:all/;

=head1 NAME
Linkspace::User::System - system user, can do everything

=head1 SYNOPSIS

=head1 DESCRIPTION
This represents a (Linux) user, which can be a daemon or someone
who is using CLI to enter commands.  This user has all rights.

=head1 METHODS: Constructors

=head1 METHODS: Permissions

=cut

#XXX This is probably too easy.  Diffentiate between 'root' and other
#XXX system users?
sub is_admin { 1 }

=head1 METHODS: Groups
We ignore the existence of system groups (for now).

=head2 \@groups = $user->groups;
Returns an empty LIST.
=cut

sub groups { [] }

1;
