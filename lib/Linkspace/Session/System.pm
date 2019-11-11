package Linkspace::Session::System;
use parent 'Linkspace::Session';

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Moo;

=head1 NAME
Linkspace::Session::System - System sessions

=head1 SYNOPSIS

=head1 DESCRIPTION
Any program which does some linkspace processing has shared needs in
the 'session' space: who is do what using which rights.  So, each script,
will initiate this object.

When the webserver is in between (or before) requests, it will have this
session object as well.

=head1 METHODS: Constructors

=head1 METHODS: Attributes

=cut

sub handles_web_request { 0 }
sub is_system { 1 }

1;
