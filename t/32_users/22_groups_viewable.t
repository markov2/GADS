# Test ::Group  groups_viewable
# Derived from old t/012_graph_permissions.t
use Linkspace::Test;

use_ok 'Linkspace::Site::Users';
use_ok 'Linkspace::Group';

my $site = test_site;
test_session;

my $groups = $site->groups;
ok defined $groups, 'Load user group handler';

my $sheet = test_sheet with_columns => 1;

my $owner = $sheet->owner;
isa_ok $owner, 'Linkspace::User::Person';

my $user1  = test_user;
my $user2  = make_user '2';

my $group1 = $sheet->group;

my $group2 = $groups->group_create({name => $group2});
$group2->add_user($user1);

ok   $user1->is_in_group($sheet->group);
ok   $user1->is_in_group($group2);
ok   $user2->is_in_group($sheet->group);
ok ! $user2->is_in_group($group2);

$sheet->group_allow($group1, 'view_group');
$sheet->update({ owner => $user2 });

# Check what groups each user can see for sharing graphs.
# Create new table with 2 new groups, which should not be shown to anyone but
# owner to begin with.  XXX
# Group3 is a group with normal read permissions on a field in the table

my $sheet2 = make_sheet '2';
my $group3  = $groups->group_create({name => 'group3'});
my $column2 = $sheet2->layout->column('string1');
$column2->group_allow($group3, 'read');


# Group4 is a group which has layout permissions on the new table
my $group4 = $groups->group_create({name => 'group4'});
$sheet->group_allow($group4, 'layout');

# Finally a third sheet with its own group to check this group is only
# shown to owner.
my $sheet3  = make_sheet '3', with_columns => 1;
my $group5  = $groups->group_create({name => 'group5'});
my $column3 = $sheet3->layout->column('string1');
$column3->group_allow($group5, 'read');

sub _viewable($)
{   my $user = shift;
    join ' ', sort grep /^group/     #XXX Why grep '^group'?
        map $_->name,
           @{$user->groups_viewable};
}

# Check viewable groups
# First normal user should see group1 and group2 that it's a member of
is _viewable($user1), 'group1 group2', "First normal user has correct groups");

# Only group1 for second normal user
is _viewable($user2), 'group1', 'Second normal user has correct groups';

# All groups for owner
is _viewable($owner), 'group1 group2 group3 group4 group5',
    'Owner has correct groups';

# Now add group4 to the normal user. This should then allow the normal user to
# also see group3 which is used in the table that group4 has layour permission
# on.

$group4->add_user($user1);
is _viewable($user1), 'group1 group2 group3 group4',
    'Normal user has access to groups in its tables';

done_testing;
