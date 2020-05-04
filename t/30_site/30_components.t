# Start the components of a Site
use Linkspace::Test;

use_ok 'Linkspace::Site';

### Create a site

my $site = Linkspace::Site->site_create({hostname => 'test.example.com'});
ok defined $site, 'Created simpelest site, id='.$site->id;
is logline, "info: Site created ${\$site->id}: test";

my $users = $site->users;
ok defined $users, 'Access to the users';
isa_ok $users, 'Linkspace::Site::Users', '...';
is $users->site, $site, '... for my site';

my $groups = $site->groups;
ok defined $users, 'Access to the groups';
is $groups, $users, '... same handler as users';

my $doc = $site->document;
ok defined $doc, 'Access to sheets';
isa_ok $doc, 'Linkspace::Site::Document', '...';
is $doc->site, $site, '... for my site';

done_testing;
