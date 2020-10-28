## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::User::System;
use warnings;
use strict;

use Log::Report 'linkspace';
use English  qw/$UID/;

use Moo;
extends 'Linkspace::User';

=head1 NAME
Linkspace::User::System - system user, can do everything

=head1 SYNOPSIS

=head1 DESCRIPTION
This represents a (Linux) user, which can be a daemon or someone
who is using CLI to enter commands.  This user has all rights.

=head1 METHODS: Constructors

=head1 METHODS: Accessors
=cut

sub BUILD
{   my ($self, $args) = @_;
    $self->{_pw} = [ getpwuid $UID ];
}

sub id       { - $UID }
sub username { $_[0]->{_pw}[0] }
sub email    { $_[0]->username . '@localhost' }
sub value    { $_[0]->[5] }

#------------
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
