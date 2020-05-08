# Test the creation of some often used objects

use Linkspace::Test;

### Site

my $site = test_site;
ok defined $site, 'Created test site';
isa_ok $site, 'Linkspace::Site', '...';
is $site->path, 'test-site', '... not the default site';

### Session

my $session = test_session;
ok defined $session, 'Created test session';
isa_ok $session, 'Linkspace::Session', '...';
is $session->site, $site, '... test site';

my $user = $session->user;
isa_ok $user, 'Linkspace::User::Person', '... user';
is $user->surname, 'Doe', '... test user';

is $::session, $session, '... installed as global';

### User

my $user1 = test_user;
ok defined $user1, 'Created test user';
is $user, $user1, '... active user is test user';

my $user2 = make_user '2';
ok defined $user2, '... create second user';
isnt $user1, $user2, '... different user';
isa_ok $user2, 'Linkspace::User::Person', '...';
is $user2->email, 'john2@example.com', '... username';

### Group

my $group1 = test_group;
ok defined $group1, 'Created test group';
isa_ok $group1, 'Linkspace::Group', '...';
is $group1->name, 'group1', '... group name';

my $group2 = make_group '2';
isnt $group1, $group2, '... new group';
is $group2->name, 'group2', '... group name';

done_testing;

