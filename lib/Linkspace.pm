
package Linkspace;

use warnings;
use strict;
use open ':encoding(utf8)';

use Log::Report 'linkspace';

use YAML             qw(LoadFile);

use Linkspace::DB    ();
use Linkspace::Site  ();
use Linkspace::Session::System ();
use Linkspace::Mailer ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

my $config_fn = $ENV{LINKSPACE_CONFIG}
    or error "Environment variable LINKSPACE_CONFIG required";

=head1 NAME
Linkspace - the Linkspace application

=head1 SYNOPSIS

  package main;
  our $linkspace = Linkspace->new(...)->start(...);
  our $linkspace = Linkspace->start(...);

=head1 DESCRIPTION
This module has main control over any application which processes Linkspace
data.  It manages the communication between the main components (singletons)
and their configuration.

=head1 METHODS: Constructors

=head2 $::linkspace = Linkspace->start(...)
Every linkspace program has a session, which simplifies logging and
permissing checking.

One component this creates is the default session object.  If no C<session>
object is passed, this requires a C<site> and C<user>.  When no C<site>
is provided, a C<host> is need which defaults to 'default_site' from
the configuration file.  If no C<user> is provided, it defaults to the
current system user.
=back

=cut

sub BUILD
{   my ($self, $args) = @_;
    $::linkspace = $self;
}

sub start
{   my $thing = shift;
    my $args  = ref $_[0] eq 'HASH' ? shift : { @_ };
    my $self  = ref $thing ? $thing : $thing->new($args);

    # This dirty global connects all singletons.  It simplifies the code
    # enormously.

    $self->db;

    unless($::session = $args->{session})
    {   my $site = $args->{site};
        unless($site)
        {   my $host = $args->{host} || $self->settings->{default_site}
                or error __x"No default_site found";

            $site = Linkspace::Site->from_hostname($host,
                locale => $self->settings_for('locale'),
            ) or error __x"Cannot find default site '{host}'", host => $host;
        }

        $::session = $self->{default_session} =
            Linkspace::Session::System->new(site => $site, user => $args->{user});
    }

    $self->start_logging($args->{log_dispatchers});
    $self;
}

#-----------------------
=head1 METHODS: attributes

=head2 my $session = $::linkspace->default_session;
Session (containing permissions and maybe default site) which will be
used when there is no user request being handled.

=cut

sub default_session { $_[0]->{default_session} }

=head2 $::linkspace->environment;
Could be C<testing>, C<development> and C<production>.  The C<testing>
configuration is (with the exception of the database configuration)
always the same: needed to produce reproducable results running the
test scripts.  The C<development> configuration has your personal
preferred configuration.

=cut

sub environment { $_[0]->settings->{environment} or panic }

=head2 $::linkspace->settings;
This is I<only> the Linkspace logic specific configuration: the
Dancer2 plugin configuration is not handled here...

You may set the C<LINKSPACE_CONFIG> environment variable to load a specific
application set-up.
=cut

has settings => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        -f $config_fn
            or error __x"Configuration file '{fn}' does not exist", fn => $config_fn;

        $config_fn =~ m/\.yml$/
            or error __x"Configuration file format of '{fn}' not (yet) supported",
                 fn => $config_fn;

        LoadFile $config_fn;
    },
);

=head2 $::linkspace->settings_for($component)
Returns a HASH which contains configuration parameters for the C<$component>
in the configuration file.  The components are top-level elements.  The
default configuration file name is F<linkspace.yml>.

Do refrain from using this method outside this class: settings should always
be applied during initiation of object, so within this class.  However, in
rare cases, abstraction is broken (at the moment)...
=cut

sub settings_for
{   my ($self, $component) = @_;
    $self->settings->{$component} || {};
}

=head2 $::linkspace->setting($component => $attribute);
Try to avoid using this outside this module.
=cut

sub setting($$)
{   my $for = $_[0]->settings_for($_[1]);
    $for ? $for->{$_[2]} : undef;
}

=head2 my $db = $::linkspace->db
Returns the L<Linkspace::DB> object which connects to the central database
with linkspace data.
=cut

has db => (
    is      => 'lazy',
    builder => sub {
        my ($self, $db) = @_;
        return $db if defined $db;

        my $dbconf = $self->settings_for('db');
        my $class  = delete $dbconf->{class} || 'Linkspace::DB';

        my ($dsn, $user, $passwd) = @{$dbconf}{qw/dsn user password/ };
        my $db_type  = $dbconf->{dsn} =~ m/^DBI\:(pg|mysql)\:/i ? lc($1)
          : error __x"Unsupported database type in dsn '{dsn}'",
               dsn => $dbconf->{dsn};

        my $options  = $dbconf->{options} ||= {};
        $options->{RaiseError}  = 1 unless exists $options->{RaiseError};
        $options->{PrintError}  = 1 unless exists $options->{PrintError};
        $options->{quote_names} = 1 unless exists $options->{quote_names};

        $options->{mysql_enable_utf8} = 1
            if ! exists $options->{mysql_enable_utf8} && $db_type eq 'mysql';

        my $sclass = delete $dbconf->{schema_class} || 'GADS::Schema';
        my $schema = $sclass->connect($dsn, $user, $passwd, $options);

        $::db = $class->new(schema => $schema);
    },
);


=head2 $::linkspace->site_for($host)
Returns the L<Linkspace::Site> object which defines one running site.  When
the site is not found, C<undef> is returned.
=cut

sub site_for($)
{   my ($self, $host) = @_;
    $host =~ s/\.$//;
    my $index = $self->{L_sites} ||= {};
    if(my $site = $index->{lc $host})
    {   return $site unless $site->has_changed('meta');
    }

    $index->{lc $host} = Linkspace::Site->from_hostname($host);
}


=head2 \@sites = $::linkspace->all_sites;
Returns a L<Linkspace::Site> object per defined site.
=cut

sub all_sites()
{   my $self = shift;
    my $index = $self->{L_sites} ||= {};
    $index->{lc $_->hostname} ||= $_
         for @{Linkspace::Site->search_objects};
    [ values %$index ];
}
    
=head2 $::linkspace->start_logging(\@dispatchers?);
Switch to dispatch (error) messages to the configure logging back-end.
=cut

sub start_logging(;$)
{   my ($self, $dispatchers) = @_;
    $dispatchers ||= $self->setting(logging => 'dispatchers') || [];
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

=head2 my $mailer = Linkspace->mailer;
=cut

sub mailer()
{   my $self = shift;
    return $self->{L_mailer} if $self->{L_mailer};

    my $mailconf = $self->settings_for('mailer') || {};

    my $prefix = $mailconf->{message_prefix} || "";
    $prefix   .= "\n" if length $prefix;

    $self->{L_mailer} = Linkspace::Email->new(
        %$mailconf,
        message_prefix => $prefix,
    );
}

1;
