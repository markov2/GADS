# Test the creation of some often used objects

use Linkspace::Test;

### Site

my $site = test_site;
isa_ok $site, 'Linkspace::Site', '...';
is $site->path, 'test-site', '... not the default site';

### Session

my $session = test_session;
isa_ok $session, 'Linkspace::Session';
is $session->site, $site, '... test site';

my $user = $session->user;
isa_ok $user, 'Linkspace::User::Person', '... user';
is $user->surname, 'Doe', '... test user';

is $::session, $session, '... installed as global';

done_testing;

