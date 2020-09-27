#!/usr/bin/env perl
# This script test creating test objects

use Linkspace::Test
    start_test_session => 0;

use Linkspace::Session::System  ();

my $site = test_site;
ok defined $site, 'Test site created';
isa_ok $site, 'Linkspace::Site', '... ';
is $site->name, 'test-site', '... name';

# The site is not passed around in the program: always $::session->site

$::session = Linkspace::Session::System->new(site => $site);

### Test user

my $user = test_user;
ok defined $user, 'Test user created';
isa_ok $user, 'Linkspace::User::Person', '... ';
ok $user->is_admin, '... created a superadmin';
is $user->organisation->name, 'My Orga', '... orga';
is $user->department->name,   'My Dept', '... dept';

### Test group

my $group = test_group;
ok defined $group, 'Test group created';
isa_ok $group, 'Linkspace::Group', '...';
ok $user->is_in_group($group), '... found test_user in group';

### Session

my $session = test_session;
ok defined $session, 'Created test session';
isa_ok $session, 'Linkspace::Session', '...';
is $session->site, $site, '... test site';
is $session->user, $user, '... test user';
is $::session, $session, '... installed as global';

done_testing;
