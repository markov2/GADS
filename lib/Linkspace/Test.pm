
package Linkspace::Test;

use warnings;
use strict;

use Log::Report    'linkspace';

use Test::More;
use Import::Into;
use Importer       ();
use Data::Dumper   qw/Dumper/;

use Linkspace;

our @EXPORT = qw/
   logline logs logs_purge
   test_site test_session
/;

our $guard;  # visible for guard test only

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    Test::More->import::into($caller);
    warnings->import::into($caller);
    strict->import::into($caller);

    $Data::Dumper::Indent   = 1;
    $Data::Dumper::Sortkeys = 1;
    Data::Dumper->import::into($caller, 'Dumper');

    Importer->import_into(__PACKAGE__, $caller, @EXPORT);

    $::linkspace = Linkspace->start(
        log_dispatchers => [ +{   # We cannot start a CALLBACK from config
            type     => 'CALLBACK',
            callback => \&log,
            mode     => 'VERBOSE',
        } ],
    );

    # All database changes get lost when the test script terminates.
    $guard = $::db->begin_work;
}

END { $guard->rollback if $guard }

### Logging

my @loglines;
sub log($$$$)
{   my ($cb, $options, $reason, $message) = @_;
    my $line = $cb->translate($options, $reason, $message);
    push @loglines, $line =~ s/\n\z//r;
}
sub logs { my @l = @loglines; @loglines = (); @l }
sub logline { @loglines ? shift @loglines : undef }
sub logs_purge() { @loglines = () }

# Call logs_purge before the end of your test-script to ignore this
END { warn "untested log: $_\n" for @loglines }


### Some objects

my ($test_site, $test_user);

sub test_site()
{   return $test_site if $test_site;

    $test_site = Linkspace::Site->site_create({
        hostname => 'test-site.example.com',
    });

    is logline, "info: Site created ${\$test_site->id}: test-site",
        "created default site ${\$test_site->id}";

    $test_site;
}

sub test_user()
{   return $test_user if $test_user;

    $test_user = $::session->site->users->user_create({
        email     => 'john@example.com',
        firstname => 'John',
        surname   => 'Doe',
    });

    is logline, "info: User created ${\$test_user->id}: test-site/john\@example.com",
        "created default user ${\$test_user->id}, John Doe";

    $test_user;
}

sub test_session()
{   # user is created in active site, switch from default to test-site first
    my $admin = $::session->user;

    if($::session->site ne test_site)
    {   $::session = Linkspace::Session->new(
           site => test_site,
           user => $admin,
        );
    }

    my $user = test_user;
    $::session->user_login($user);
    is logline, "info: login_success Successful login ${\$user->username} by admin ${\$admin->username}",
        '... logged login in audit';

    is logline,
        "info: User ${\$user->id}='${\$user->path}' changed fields: failcount lastfail",
        '... logged reset login-failure count';

    $::session;
}

1;
