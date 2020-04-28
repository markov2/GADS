package Linkspace::Session;

use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Audit ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use Scalar::Util  qw(blessed);

=head1 NAME
Linkspace::Session - dancer2 and CLI sessions

=head1 SYNOPSIS

=head1 DESCRIPTION
This module manages the single use of Linkspace.  It attempts to hide
differences between Dancer2 (website) and command-line (CLI) access to
the Linkspace logic.

=head1 METHODS: Constructors

=head1 METHODS: Attributes

=head2 my $site = $session->site;

=cut

has site => (
    is       => 'ro',
    required => 1,
);


=head1 METHODS: User related

=head2 my $user = $session->user;

=head2 $session->set_user($user);

On any moment, there is a user known.  This could either be the user
which started the script (f.i. the web daemon) or the person who is
being served via HTTP requests for web pages or REST.

=cut

has user => (
    is       => 'rw',
    isa      => InstanceOf['Linkspace::User'],
    required => 1,
);

=head2 $session->user_login($user)
=cut

sub user_login
{   my ($self, $user) = @_;
    $self->audit("Successful login by username ".$user->username,
        type => 'login_success',
    );

    $self->set_user($user);

    $user->update({
        failcount => 0,
        lastfail  => undef,
    });
}

=head2 $session->user_logout;
=cut

sub user_logout
{   my $self = shift;
    $self->audit('Logging-out', type => 'logout');
}

=head2 $session->audit($description, @fields);
Write a line of use related action history.
=cut

sub audit
{    my ($self, $descr, %log) = @_;
     $log{description} = $descr;
     $log{user_id}   ||= $self->user->id;
     $log{datetime}  ||= DateTime->now;
     $log{type}      ||= 'user_action';
     Linkspace::Audit->log(\%log);
}

#--------------------
=head1 METHODS: Request related

=head2 $session->handles_web_request;
Returns a true value when a L<Dancer2::Session> object is used.
=cut

sub handles_web_request { panic }

=head2 $session->is_cli;
Returns a true value when the session serves a command-line user.
=cut

sub is_system { panic }


1;