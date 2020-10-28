## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Session::Dancer;
use parent 'Linkspace::Session', 'Dancer2::Session::YAML';

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Moo;

=head1 NAME
Linkspace::Session::Dancer - Dancer sessions

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS: Constructors

=head1 METHODS: Attributes

=cut

sub handles_web_request { 1 }
sub is_system { 0 }

1;
