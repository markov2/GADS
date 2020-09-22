# Test the creation (user permission) groups
use Linkspace::Test;

use_ok 'Linkspace::Site::Users';
use_ok 'Linkspace::Group';

my $site = test_site;

my $groups = $site->groups;
ok defined $groups, 'Load user group handler';
isa_ok $groups, 'Linkspace::Site::Users', '... handled by ::Users object';

### Create first group

my $all1 = $groups->all_groups;
cmp_ok @$all1, '==', 1, '... no groups yet';  # +test_group

my $g1 = $groups->group_create({name => 'group1'});
ok defined $g1, 'Created first group';
isa_ok $g1, 'Linkspace::Group', '...';
is $g1->name, 'group1', '... right name';
is $g1->site_id, $site->id, '... right site';
is_deeply $g1->default_permissions, [], '... default permissions';

my $g1_id = $g1->id;
my $path1 = $g1->path;
is logline, "info: Group created $g1_id: $path1", '... logged';

my $all2 = $groups->all_groups;
cmp_ok @$all2, '==', 2, '... indexed first group'; # new+test_group
is $all2->[1], $g1, '... is first created group';

my $g1b = $groups->group($g1_id);
ok defined $g1b, '... addressed first group by id';
is $g1b, $g1, '... ... is same object';

my $g1c = $groups->group($g1_id);
ok defined $g1c, '... addressed first group by object';
is $g1c, $g1, '... ... is same object';

my $g1d = $groups->group('group1');
ok defined $g1d, '... addressed first group by name';
is $g1d, $g1, '... ... is same object';

my $g1f = Linkspace::Group->from_id($g1_id);
ok defined $g1f, 'Load first from database';
isa_ok $g1f, 'Linkspace::Group', '...';
is $g1f->name, 'group1', '... right name';

### Create second group

my @all_perms = qw/
    approve_existing
    approve_new
    read
    write_existing
    write_existing_no_approval
    write_new
    write_new_no_approval
/;

my $g2 = $groups->group_create({name => 'group2',
    (map +("default_$_" => 1), @all_perms),
});

ok defined $g2, 'Created second group';
isnt $g2, $g1, '... is different group';
is logline, "info: Group created ${\$g2->id}: ${\$g2->path}", '... logged';

my $all3 = $groups->all_groups;  # ordered alphabetically
cmp_ok @$all3, '==', 3, '... indexed two groups';   # 2 created + test_group
is $all3->[0], test_group, '... test_group';
is $all3->[1], $g1, '... is first created group';
is $all3->[2], $g2, '... is second created group';


#### Permissions

is_deeply $g1->default_permissions, [],
    'group1 permissions: none';

is_deeply $g2->default_permissions, \@all_perms,
    'group2 permissions: all';

#### Update

my $g1e = $groups->group_update($g1, {
    name              => 'group1b',
    default_read      => 1,
    default_write_new => 1,
});
ok defined $g1e, 'Modified first group';
is $g1e, $g1, '... same object';
is $g1e->name, 'group1b', '... changed name';
my $path = $g1e->path;
is $path, 'test-site/group1b', '... path changed';
is_deeply $g1e->default_permissions, [ qw/read write_new/ ],
    '... changed permissions';

is logline, "info: Group $g1_id changed name from 'group1' into 'group1b'",
    '... logged name change';

is logline, "info: Group $g1_id='$path' changed fields: default_read default_write_new name",
    '... logged record change';

#### Delete

ok $groups->group_delete($g1), 'Delete first group';
ok logline, "info: Group $g1_id='$path' deleted";

ok ! Linkspace::Group->from_id($g1_id), '... disappeard from db';
my $g2b = Linkspace::Group->from_id($g2->id);
ok defined $g2b, '... second group still there';

my $all4 = $groups->all_groups;
cmp_ok @$all4, '==', 2, '... removed from group index';  # 3-1=2

done_testing;
