
package Linkspace;

use warnings;
use strict;
use open ':encoding(utf8)';

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use YAML             qw(LoadFile);

use Linkspace::DB    ();
use Linkspace::Site  ();
use Linkspace::Util  qw(configure_util);
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

The L<Linkspace::Session::System> object prefers the specific C<site>, otherwise
only limited database lookups are possible.

=item config FILENAME

Which configuration file to use for everything except the Dancer2 specifics.
It defaults to 'linkspace.yml' in the current directory (which is not really
safe).

=back

=cut

sub BUILD {
    my ($self, %args) = @_;

    my $settings = $self->settings;
    configure_util $settings;

    $self->_configure_logging;

    my $host = $args{host} || $settings->{default_website}
        or error __x"No default site found";

    my $site = Linkspace::Site->find($host)
        or error __x"Cannot find default site '{host}'", host => $host;

    $::session = $self->{default_session} = Linkspace::Session::System->new(
        site => $site,
    );

    {};
}


=head1 METHODS: attributes

=head2 my $session = $::linkspace->default_session;
Session (containing permissions and maybe default site) which will be
used when there is no user request being handled.

=cut

sub default_session { $_[0]->{default_session} }

# private
has config_fn => (
    is      => 'ro',
    default => 'linkspace.yml',
);

=head2 $::linkspace->settings
This is I<only> the Linkspace logic specific configuration: the
Dancer2 plugin configuration is not handled here...
=cut

has settings => (
    is      => 'ro',
    isa     => HashRef,
    builder => sub {
        my ($self, $spec) = @_;

        if(defined $spec)
        {   ref $spec eq HASH or panic "settings() expects HASH";
            return $spec;
        }

        my $fn = $self->config_fn;
        -f $fn or error __x"Configuration file '{fn}' does not exist", fn => $fn;

        $fn =~ m/\.yml$/
             or error __x"Configuration file format of '{fn}' not (yet) supported",
                 fn => $fn;

        my $config = LoadFile $fn;

        $config;
    },
);

sub _settingsFor
{   my ($self, $component) = @_;
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
        my $dbconf = $self->_settingsFor('db');
        my $class    = delete $dbconf->{class} || 'Linkspace::DB';
        $dbconf->{schema_class} ||= 'Linkspace::Schema';

        my $db_type  = $dbconf->{dsn} =~ m/^DBI\:(pg|mysql)\:/i ? lc($1)
          : error __x"Unsupported database type in dsn '{dsn}'",
               dsn => $dbconf->{dsn};

        my $options  = $dbconf->{options} ||= {};
        $options->{RaiseError} //= 1;
        $options->{PrintError} //= 1;
        $options->{quote_names}  = 1;
        $options->{mysql_enable_utf8} //= 1 if $db_type eq 'mysql';
        $class->new(%$dbconf);
    },
);


=head2 $::linkspace->site_for($host)
Returns the L<Linkspace::Site> object which defines one running site.  When
the site is not found, C<undef> is returned.

The usual access to the active site is via C<<session->site>>.
=cut

sub site_for {
{   my ($self, $host) = @_;
    $host =~ s/\.$//;
    $self->{sites}{lc $host} ||= Linkspace::Site->find($host);
}


=head2 $::linkspace->start_logging;
Switch to dispatch (error) messages to the configure logging back-end.
=cut

sub start_logging()
{   my $self = shift;

    my $logconf = $self->_settingsFor('logging')
        or return;

    my $dispatchers = $logconf->{dispatchers} || [];
    @$dispatchers or return;   # leave default

    dispatcher 'do-not-reopen';

    # Do not close standard 'default' too early, otherwise may loose errors
    # during configuration.
    my $has_new_default = 0;

    foreach my $d (@$dispatchers)
    {   my $type = delete $d->{type} || 'SYSLOG';
        my $name = delete $d->{name} || 'default';
        dispatcher $type => $name, charset => 'utf8', %$d;

        $has_new_default = 1 if $name eq 'default';
    }

    dispatcher close => 'default'
        unless $has_new_default;
}

1;
