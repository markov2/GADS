# Test Linkspace::DB::Table create and update

use Linkspace::Test start_test_session => 0;

# Let's use Linkspace::Site: it does not depend on anything else, and
# implements no object caching.
my $class = 'Linkspace::Site';

use_ok $class, 'A simple top-level element';
isa_ok $class, 'Linkspace::DB::Table';

ok ! $class->from_id(-1), 'Cannot load from missing id';
ok ! defined $class->from_record(undef), 'Loading record undef';
ok ! defined $class->from_hostname('test_host'), 'Loading unknown host';
ok ! defined $class->from_name('test_name'), 'Loading unknown name';

### Create

my $site = $class->site_create({
    name     => 'create_name',
    hostname => 'create_host',
});

ok defined $site, 'Site got created';
isa_ok $site, $class, '...';
isa_ok $site, 'Linkspace::DB::Table', '...';
is $site->name, 'create_name', '... right name';
is $site->hostname, 'create_host', '... right hostname';

my $site_id = $site->id;
is logline, "info: Site created $site_id: create_name", '... got logged';
is $site->path, 'create_name', '... path='.$site->path;

my $by_id = $class->from_id($site_id);
ok defined $by_id, "Found via site id: $site_id";
is $by_id->id, $site_id, '... is same site';
isnt $by_id, $site, '... is different object';

my $by_search = $class->from_search({hostname => { -like => 'create%' }});
ok defined $by_search, 'Found via hostname match';
is $by_search->id, $site->id, '... is same site';
isnt $by_search, $site, '... is different object';

my $by_host = $class->from_hostname('create_host');
ok defined $by_host, 'Found via site hostname';
is $by_host->id, $site_id, '... is same site';
isnt $by_host, $site, '... is different object';

my $by_name = $class->from_name('create_name');
ok defined $by_name, 'Found via site name';
is $by_name->id, $site_id, '... is same site';
isnt $by_name, $site, '... is different object';

### Create lazy

my $site5a = $class->site_create({name => 'lazy create', hostname => 'dummy'}, lazy => 1);
ok ! defined $site5a, 'Lazy create: no object';
ok ! logline, '... not logged either';

my $site5 = $class->from_name('lazy create');
my $site5_id = $site5->id;
ok defined $site5, '... but exists as '.$site5_id;
cmp_ok $site5_id, '!=', $site_id, '... different site than the first';

### Update

ok $site->site_update({ name => 'new name'}), 'Changed site';
is $site->name, 'new name', '... see change';
is $site->path, 'new name', '... path='.$site->path;
ok $site->has_changed(meta => 0),  '... site meta changed';
ok ! $site->has_changed('meta'),  '... changed flag was reset';
is logline, "info: Site $site_id='new name' changed fields: name", '... was logged';

my $site2 = $class->from_id($site_id);
isnt $site2, $site, 'Reloaded the site from the db';
is $site2->name, 'new name', '... see change';

ok $site->site_update({ name => 'newer name'}, lazy => 1), 'Changed site again';
is $site->name, 'new name', '... lazy, so do not see change';
ok ! defined logline, '... lazy, so no log';
ok $site->has_changed('meta'), '... but flagged site change';

### Delete

ok $site5->site_delete, 'Delete the second site';
ok $site5->has_changed('meta'), '... flag change';
ok $class->from_id($site_id), '... first site was not destroyed';
is logline, "info: Site $site5_id='lazy create' deleted", '... deletion logged';

done_testing;
