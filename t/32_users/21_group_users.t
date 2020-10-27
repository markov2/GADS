# Test the relation be groups and its users.
use Linkspace::Test;

use_ok 'Linkspace::Site::Users';
use_ok 'Linkspace::Group';

my $site = test_site;

# test user always member of test group: avoid both
my $user2  = make_user '2';
my $group2 = make_group '2';

my $groups = $site->groups;
ok defined $groups, 'Load user group handler';

my $path   = $group2->path;

### Adding

my $a1 = $group2->users;
ok defined $a1, 'Group has no users (yet)';
cmp_ok @$a1, '==', 0, '... none';

ok $groups->group_add_user($group2, $user2), 'Add user to group';
ok $user2->is_in_group($group2), '... user knows it, with group object';
ok $user2->is_in_group($group2->id), '... user knows it, with group id';
ok ! $user2->is_in_group(-1), '... user not in other groups';

ok $group2->has_user($user2), '... group knows it, with user object';
ok $group2->has_user($user2->id), '... group knows it, with user id';
ok ! $group2->has_user(-1), '... group not has other users';

is logline, "info: user ${\$user2->email} added to $path",
    '... user addition logged';

my $a2 = $group2->users;
cmp_ok @$a2, '==', 1, '... all users is one';

# check user relation without loading all groups: db lookup
my $group2b = Linkspace::Group->from_id($group2->id);
ok defined $group2b, 'Reload group from db';
ok $group2b->has_user($user2), '... contains user by object';
ok $group2b->has_user($user2->id), '... contains user by id';

### Removing

ok $groups->group_remove_user($group2, $user2), 'Remove user from group';
ok ! $user2->is_in_group($group2), '... user knows it, with group object';
ok ! $user2->is_in_group($group2->id), '... user knows it, with group id';
ok ! $group2->has_user($user2), '... group knows it, with user object';
ok ! $group2->has_user($user2->id), '... group knows it, with user id';
is logline, "info: user ${\$user2->email} removed from $path",
    '... logged removal';

my $group2c = Linkspace::Group->from_id($group2->id);
ok defined $group2c, 'Reload group from db';

my $a3 = $group2->users;
cmp_ok @$a3, '==', 0, '... user has gone';

### Bulk set groups for user (used in create and update)

my $group3 = make_group '3';
my $group4 = make_group '4';
my $group5 = make_group '5';

ok $user2->_set_groups([$group2, $group3, $group4, $group5]),
    'Group-id bulk update';

my $ug1 = $user2->groups;
cmp_ok scalar @$ug1, '==', 4, '... user added to 4 groups';
cmp_ok scalar logs, '==', 4+1, '... logging'; # 4x add + remove test_group

ok $user2->_set_groups([$group3, $group5]), '... remove 2 groups';

my $ug2 = $user2->groups;
cmp_ok scalar @$ug2, '==', 2, '... user now in 2 groups';
is $ug2->[0], $group3, '... ... group3';
is $ug2->[1], $group5, '... ... group5';

cmp_ok scalar logs, '==', 2, '... logging'; # 2x remove

done_testing;

