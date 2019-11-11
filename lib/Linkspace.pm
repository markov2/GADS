
package Linkspace;

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Dancer2;   # config

use Linkspace::DB   ();
use Linkspace::Site ();
use Linkspace::Session::System ();

=head1 NAME
Linkspace - the Linkspace application

=head1 SYNOPSIS

  package main;
  our $linkspace = Linkspace->new(...);

=head1 DESCRIPTION
This module has main control over any application which processes Linkspace
data.  It manages the communication between the main components (singletons)
and their configuration.

=head1 METHODS: Constructors

=head2 $::linkspace = Linkspace->new(...)
Every linkspace program has a session, which simplifies logging and
permissing checking.

Options:

=over 4

=item site HOSTNAME

The L<Linkspace::Session::CLI> object prefers the specific C<site>, otherwise
only limited database lookups are possible.

=back

=cut

sub BUILD {
	my ($self, %args) = @_;

    #XXX needs support for settings

    $::session = $self->{default_session} = Linkspace::Session::CLI->new(
        site => $args{host},
    );

    {};
}


=head1 METHODS: attributes

=head2 my $session = $::linkspace->default_session;
Session (containing permissions and maybe default site) which will be
used when there is no user request being handled.

=cut

sub default_session { $_[0]->{default_session} }


=head2 $::linkspace->settings
This is I<only> the Linkspace logic specific configuration: the
Dancer2 plugin configuration is not handled here... because it is
already active before this application object gets initiated.
=cut

has settings => (
    is      => 'ro',
    isa     => HashRef,
	builder => sub {
        my ($self, $spec) = @_;

          ! defined $spec     ? config->{linkspace}
        : ref $spec eq 'HASH' ? $spec
        #XXX we may want to be able to specify a file
        : error __x"db config '{spec}' not (yet) supported", spec => $spec;
            
    },
);

sub _settingsFor {
    my ($self, $component) = @_;
    $self->settings->{$component} || {};
}

=head2 $::linkspace->db
Returns the L<Linkspace::DB> object which connects to the central database
with linkspace data.
=cut

has db => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        Linkspace::DB->new(
            %{$self->_settingsFor('db')},
        );
    },
);

=head2 $::linkspace->siteFor($host)
Returns the L<Linkspace::Site> object which defines one running site.  When
the site is not found, C<undef> is returned.

The usual access to the active site is via C<<session->site>>.
=cut

sub siteFor {
    my ($self, $host) = @_;
    $host =~ s/\.$//;
    $self->{sites}{lc $host} ||= Linkspace::Site->find($host);
}

1;
