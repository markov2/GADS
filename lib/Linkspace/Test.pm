
package Linkspace::Test;

use warnings;
use strict;

use Log::Report    'linkspace';

use Test::More;
use Import::Into;
use Importer       ();
use Data::Dumper   qw/Dumper/;
use Test::MockTime (); # Load before DateTime
use DateTime       ();

use Linkspace;

our @EXPORT = qw/
   logline logs logs_purge
   test_session switch_user
   make_site    test_site
   make_user    test_user
   make_group   test_group
   make_sheet   test_sheet
/;

sub test_site(@);    sub make_site($@);   my $test_site;
sub test_user(@);    sub make_user($@);   my $test_user;
sub test_group(@);   sub make_group($@);  my $test_group;
sub test_session(@); sub make_session(@); my $test_session;
sub test_sheet(@);   sub make_sheet($@);  my $test_sheet;

our $guard;  # visible for guard test only

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    warnings->import::into($caller);
    strict->import::into($caller);
    Log::Report->import::into($caller);
    Test::More->import::into($caller);
    Test::MockTime->import::into($caller, ':all');

    $Data::Dumper::Indent    = 1;
    $Data::Dumper::Sortkeys  = 1;
    $Data::Dumper::Quotekeys = 0;
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
    $guard = $::db->begin_work
        unless exists $args{db_rollback} && !$args{db_rollback};

    test_session
        unless exists $args{start_test_session} && !$args{start_test_session};
}

END { $guard->rollback if $guard }

###
### Logging
###

my @loglines;
sub log($$$$)
{   my ($cb, $options, $reason, $message) = @_;
    my $line = $cb->translate($options, $reason, $message);
    die $line if $reason eq 'PANIC';

    push @loglines, $line =~ s/\n\z//r;
}
sub logs { my @l = @loglines; @loglines = (); @l }
sub logline { @loglines ? shift @loglines : undef }
sub logs_purge() { @loglines = () }

# Call logs_purge before the end of your test-script to ignore this
END { warn "untested log: $_\n" for @loglines }


###
### Create initial test objects
###

# These objects are created test scripts t/22_* and removed in t/99_.
# They will stick in the database for the all tests between these
# two script names.  All other scripts run their actions in a
# 'begin-work/rollback' mode, so should not cause lastig changes.



###
### Help construct various objects
###

### Site

sub make_site($@)
{   my ($seqnr, %args) = @_;
    my $host = $args{hostname} ||= "test-$seqnr.example.com";
    my $site = Linkspace::Site->site_create(\%args);

    my $base = $host =~ s/\..*//r;
    is logline, "info: Site created ${\$site->id}: $base",
        "created site ${\$site->id}";

    $site;
}

my ($test_orga, $test_dept);
sub test_orga { $test_orga  ||= test_site->workspot_create(organisation => 'My Orga') }
sub test_dept { $test_dept  ||= test_site->workspot_create(department   => 'My Dept') }

sub test_site(@)
{   $test_site ||= make_site 0,
        hostname => 'test-site.example.com',
        ;
}


### User

sub make_user($@)
{   my ($seqnr, %args) = @_;
    my $site    = $args{site} || $::session->site;
    my $postfix = $seqnr || '';
    my $perms   = $args{permissions};
    my $email   = $args{email} ||= "john$postfix\@example.com";

    my $user = $site->users->user_create({
        firstname   => "John$postfix",
        surname     => "Doe$postfix",
        organisation=> test_orga,
        department  => test_dept,
        permissions => $perms,
        %args,
    });

    is logline, "info: User created ${\$user->id}: ${\$site->path}/$email",
        "created user ${\$user->id}, ".$user->path;

    is logline, "info: User ${\$user->path} add permission '$_'", "... perm $_"
        for @{$perms || []};

    # All users are in the $test_group.  Recursive problem with test_group/test_user
    if($postfix)
    {   test_site->groups->group_add_user(test_group, $user);
        like logline, qr/^info: user.*added to.*/;
    }

    $user;
}

sub test_user(@)
{   $test_user ||= make_user 0,
        email       => 'test_user@example.com',
        permissions => [ 'superadmin' ],
        @_;
}


### Group

sub make_group($@)
{   my ($seqnr, %args) = @_;
    my $site  = delete $args{site} || $::session->site;
    my $name  = $args{name} ||= "group$seqnr";
    my $owner = delete $args{owner};

    my $group = $site->groups->group_create(\%args);

    is logline, "info: Group created ${\$group->id}: ${\$site->path}/$name",
        "created group ${\$group->id}, ".$group->path;

    if($owner)
    {   $site->groups->group_add_user($group, $owner);
        is logline, "info: user ${\($owner->username)} added to ${\($group->path)}", '... add user';
    }
    $group;
}

sub test_group(@)
{   $test_group ||= make_group 0,
        name  => 'test_group',
        owner => test_user,
        @_;
}

sub test_session(@)
{   # user is created in active site, switch from default to test-site first
    my %args  = @_;
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

sub switch_user($)
{   my ($user) = @_;

    $::session->user_login($user);
    like logline, qr!^info: login_success .* by admin!, 'switch to user '.$user->path;
    like logline, qr!^info: User .* changed fields!, '... successfull login';
}

#XXX to be tested
sub make_sheet($@)
{   my ($seqnr, %args) = @_;
    $args{name} ||= "sheet $seqnr";

    my $with_columns = delete $args{with_columns};  #XXX TBI

    my $sheet = test_site->document->sheet_create(\%args);

    is logline, "info: Instance created ${\$sheet->id}: ${\$sheet->path}",
        '... logged creation of sheet '.$sheet->path;

    my $internal = $sheet->layout->columns_search(only_internal => 1);
    like logline, qr/^info: Layout created .*=$_/, "... log create column $_"
        for map $_->name_short, @$internal;
    $sheet;
}

sub test_sheet(@)
{   return $test_sheet if $test_sheet;

    $test_sheet = make_sheet 0,
        name_short => 'test_sheet',
        @_;

    # The $test_group contains all generated users with superadmin rights
    $test_sheet->access->group_allow(test_group, qw/layout view_create/);

    like logline, qr/^info: InstanceGroup created.*layout/,
        '... test_user can layout';

    like logline, qr/^info: InstanceGroup created.*view_create/,
        '... test_user can view_create';

    $test_sheet;
}

1;
__END__
###
### Helpers to fill a sheet
###

my %dummy_file_data = (
    name     => 'myfile.txt',
    mimetype => 'text/plain',
    content  => 'My text file',
);

sub _default_rag_code($) { my $seqnr = shift; <<__RAG }
function evaluate (L${seqnr}daterange1)
    if type(L${seqnr}daterange1) == \"table\" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == \"table\" and next(L${seqnr}daterange1) == nil then
        dr1 = nil
    else
        dr1 = L${seqnr}daterange1
    end
    if dr1 == nil then return end
    if dr1.from.year < 2012 then return 'red' end
    if dr1.from.year == 2012 then return 'amber' end
    if dr1.from.year > 2012 then return 'green' end
end
__RAG

sub _default_calc_code($) { my $seqnr = shift;  <<__CALC }
function evaluate (L${seqnr}daterange1)
    if type(L${seqnr}daterange1) == \"table\" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == \"table\" and next(L${seqnr}daterange1) == nil then
        dr1 = nil
    else
        dr1 = L${seqnr}daterange1
    end
    if dr1 == null then return end
    return dr1.from.year
end
__CALC

my @default_sheet_rows = (   # Don't change these: some tests depend on them
    {   string1    => 'Foo',
        integer1   => 50,
        date1      => '2014-10-10',
        enum1      => 1 + $config->{curval_offset},
        daterange1 => ['2012-02-10', '2013-06-15'],
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        enum1      => 2 + $config->{curval_offset},
        daterange1 => ['2008-05-04', '2008-07-14'],
    },
);
1;
