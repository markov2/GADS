# Test the creation (user permission) groups
use Linkspace::Test;

use_ok 'Linkspace::Site::Users';
use_ok 'Linkspace::Group';

my $site = test_site;
test_session;

my $groups = $site->groups;
ok defined $groups, 'Load user group handler';
isa_ok $groups, 'Linkspace::Site::Users', '... handled by ::Users object';

done_testing;
