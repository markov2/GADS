#!/usr/bin/env perl
# This script creates the test-site, which stays alive until all script
# have run.  See t/99_linkspace_test/10_cleanup.t

use Linkspace::Test
    db_rollback        => 0,
    start_test_session => 0;

my $site = test_site;

# We cannot use test_session() yet, because we have no user to login.
$::session = Linkspace::Session::System->new(site => $site);


### Test user

my $username = Linkspace::Test::_name_test_user;
my $user;
if($user = $site->users->user_by_name($username))
{   ok 1, "Test user $username did still exist";
}
else
{   $user = make_user 0 =>
        site        => $site,
        email       => $username,
        permissions => ['superadmin'];
    ok defined $user, "Test user $username created";
}

isa_ok $user, 'Linkspace::User::Person', '... ';
ok $user->is_admin, '... created a superadmin';


### Test group

my $group_name = Linkspace::Test::_name_test_group;

my $group;
if($group = $site->groups->group($group_name))
{   ok 1, "Test group $group_name did still exist";
}
else
{   $group = make_group 0 =>
        site        => $site,
        name        => $group_name,
        owner       => $user;
    ok defined $group, "Test group $group_name created";

    $site->groups->group_add_user($group, $user);
    like logline, qr/^info: user.*added to.*/, '... log added user to group';
}

isa_ok $group, 'Linkspace::Group', '...';

done_testing;
