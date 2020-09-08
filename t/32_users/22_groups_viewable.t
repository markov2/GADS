# Test ::Group  groups_viewable
# Derived from old t/012_graph_permissions.t

#XXX TESTS STILL FAILING
use Linkspace::Test;

use_ok 'Linkspace::Site::Users';
use_ok 'Linkspace::Group';

my $site   = test_site;

my $groups = $site->groups;
ok defined $groups, 'Load user group administrator';

plan skip_all => 'needs filling in test_sheet';
my $sheet  = test_sheet with_columns => 1;
my $user1  = make_user '2';
my $user2  = make_user '3';

# All created users are added to the default group of our test sheet.
my $group1 = test_group;
ok $user1->is_in_group($group1);
ok $user2->is_in_group($group1);

$sheet->access->group_allow($group1, 'view_group');
like logline, qr/^info: InstanceGroup create.*group1=view_group$/,
    'group1 can view_group';

# Create a second group
my $group2 = $groups->group_create({name => 'group2'});
is logline, "info: Group created ${\($group2->id)}: test-site/group2", 'Group2 created';

$groups->group_add_user($group2, $user1);
like logline, qr!^info: user .* added to test-site/group2!, 'Add user to group2';
ok   $user1->is_in_group($group2);
ok ! $user2->is_in_group($group2);
switch_user $user2;

# Check what groups each user can see for sharing graphs.
# Create new table with 2 new groups, which should not be shown to anyone but
# user2 to begin with.
# Group3 is a group with normal read permissions on a field in the table

my $sheet2  = make_sheet '2';
my $group3  = $groups->group_create({name => 'group3'});
my $column2 = $sheet2->layout->column('string1');
$column2->group_allow($group3, 'read');

# Group4 is a group which has layout permissions on the new table
my $group4 = $groups->group_create({name => 'group4'});
$sheet->access->group_allow($group4, 'layout');

# Finally a third sheet with its own group to check this group is only
# shown to owner.
my $sheet3  = make_sheet '3', with_columns => 1;
my $group5  = $groups->group_create({name => 'group5'});
my $column3 = $sheet3->layout->column('string1');
$column3->group_allow($group5, 'read');

sub _viewable($)
{   my $user = shift;
    join ' ', sort map $_->name, @{$user->groups_viewable};
}

# Check viewable groups
# First normal user should see group1 and group2 that it's a member of
is _viewable($user1), 'group1 group2', "First normal user has correct groups";

# Only group1 for second normal user
is _viewable($user2), 'group1', 'Second normal user has correct groups';

is _viewable($user1), 'group1 group2 group3 group4 group5',
    'First user has correct groups';

# Now add group4 to the normal user. This should then allow the normal user to
# also see group3 which is used in the table that group4 has layour permission
# on.

$groups->group_add_user($group4, $user1);
is _viewable($user1), 'group1 group2 group3 group4',
    'Normal user has access to groups in its tables';

done_testing;
