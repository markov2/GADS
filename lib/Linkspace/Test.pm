
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
   test_session
   make_site    test_site
   make_user    test_user
   make_group   test_group
   make_sheet
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

my ($test_site, $test_user, $test_group);

sub make_site($@)
{   my ($seqnr, %args) = @_;
    my $host  = $seqnr==1 ? 'test-site' : "site$seqnr";

    my $site = Linkspace::Site->site_create({
        hostname => "$host.example.com",
    });

    is logline, "info: Site created ${\$site->id}: $host",
        "created site ${\$site->id}";

    $site;
}
sub test_site(@) { $test_site ||= make_site '1', @_ } 


sub make_user($@)
{   my ($seqnr, %args) = @_;
    my $site = $args{site} || $::session->site;
    my $postfix = $seqnr==1 ? '' : $seqnr;
    my $perms   = delete $args{permissions};

    my $user = $site->users->user_create({
        email       => "john$postfix\@example.com",
        firstname   => "John$postfix",
        surname     => "Doe$postfix",
        permissions => $perms,
    });

    is logline, "info: User created ${\$user->id}: ${\$site->path}/john$postfix\@example.com",
        "created user ${\$user->id}, ".$user->path;

    is logline, "info: User ${\$user->path} add permission '$_'", "... perm $_"
        for @{$perms || []};

    $user;
}

sub test_user(@)
{   $test_user ||= make_user '1',
        permissions => ['superadmin'],
        @_;
}

sub make_group($@)
{   my ($seqnr, %args) = @_;
    my $site  = $args{site} || $::session->site;
    my $group = $site->groups->group_create({name => "group$seqnr"});

    is logline, "info: Group created ${\$group->id}: ${\$site->path}/group$seqnr",
        "created group ${\$group->id}, ".$group->path;

    $group;
}
sub test_group(@) { $test_group ||= make_group '1', @_ }

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
