# Test view access/owner rights
# Extracted from t/011_views.t

use Linkspace::Test
    not_ready => 'Waits for View components to be completed';

#XXX probably falls apart in 3 separate test-files

my $sheet      = make_sheet 1;
my $layout = $sheet->layout;

my $user_admin = test_user;  # also owns the sheet

# Standard users with permission to create views
my $user1 = make_user '2', permissions => ['view-create'];
my $user2 = make_user '3', permissions => ['view-create'];

# User with manage group views
my $user_view_group  = make_user '4', permissions => [qw/view_create view_group/];

# User with no manage view permissions
my $user_nothing = make_user '5';

my $views  = $sheet->views;
my $groups = test_site->groups;

### User private views

switch_user $user_nothing;

try { $views->view_create({name => 'view1'}) };
like $@->wasFatal->message, qr/does not have permission to create new views/,
   "Failed to create view as user without permissions";

### Create normal view as normal user

switch_user $user1;
my $view1 = $views->view_create({
    name    => 'view1',
    global  => 0,
    columns => [ $layout->column('string1')->id ],
});
ok defined $view1, "Created normal view as normal user";

# Try and read view as other user

switch_user $user2;
my $view1b = try { $views->view($view1->id)->filter }
ok $@->wasFatal->message, "Failed to read view as normal user of other user view";
ok ! defined $view1b;


foreach my $test (qw/is_admin is_global is_admin/) # Do test, change, then back again
{
    # Create view as user with group view permission
    switch_user $user_view_group;
    try { $view1->update({ $test => 1 }) };
    ok $@, "Failed to write $test view as view_group user and no group";

    try { $view1->update({ $test => 1, group => $sheet->group }) };
    my $success = $test eq 'global';
    ok $success ? !$@ : $@, "Created view with group as view_group user test $test";

    # Read group view as normal user in that group, only if global view not admin view
    switch_user $user_admin;
    $groups->group_add_user($sheet->group, $user2);

    switch_user $user2;
    my $view1c = $views->view($view1->id);
    my $current_groups = $user2->groups;
    try { $view1c->filter };
    ok $success ? !$@ : $@, "Read group view as normal user of $test view in that group";

    my $has_view = grep $_->id == $view1->id, @{$views->user_views_all};
    ok $success && $has_view || !$success, "User has view in list of available views";

    # Read group view as normal user not in that group
    switch_user $user_admin;
    $groups->group_remove_user($_, $user2) for $user2->groups;

    switch_user $user2;
    try { $views->view($view1->id)->filter };
    ok $@, "Read group view as normal user of $test view not in that group";

    my $has_view2 = grep $_->id == $view1->id, @{$views->user_views_all};
    ok $success && !$has_view2 || !$success, "User has view in list of available views";

    # Return to previous setting
    switch_user $user_admin;
    $groups->group_add_user($_ => $user2) for @$current_groups;

    # Now as admin user
    $views->view_update($view1, {group_id => undef});
    ok !$@, "Created $test view as admin user";

    # Read global view as normal user
    switch_user $user2;
    my $view1d = try { $views->view($view1->id) };
    ok !$@, "Read view as normal user of $test view";
}

# Check that user ID is written correctly for global/personal

{
    switch_user $user_admin;
    my $view2 = $views->view_create({name => 'view2'});
    is $view2->owner_id, $user_admin->id, "User ID set for personal view";

    $view2->view_update({is_global => 1});
    ok ! defined $view2->owner_id, 'User ID not set for global view';

    $view2->update({is_global => 0});
    ok defined $view2->owner_id, 'User ID set back for personal view';

    $views->view_delete($view2);
}

# Test edit other user views functionality
{
    switch_user $user1;
    my $view3 = $views->view_create({name => 'FooBar'});

    switch_user $user2;
    my $has_view = grep $_->name eq 'FooBar', @{$views->user_views_all};
    ok !$has_view, "Normal user cannot see views of others";
    
    switch_user $user_admin;
    $has_view = grep $_->name eq 'FooBar', @{$views->user_views_all};
    ok $has_view, "Admin user can see views of others";

    # Then creating views for other users
    switch_user $user1;
    my $view4 = $views->view_create(name => 'FooBar2', owner => $user2);

    $has_view = grep { $_->name eq 'FooBar2' } @{$views->user_views_all};
    ok $has_view, "Normal user created own view when trying to be other user";

    switch_user $user2;
    $has_view = grep { $_->name eq 'FooBar2' } @{$views->user_views_all};
    ok(!$has_view, "Normal user cannot create view as other user");

    switch_user $user_admin;
    my $view5 = $views->view_create({name => 'FooBar3', owner => $user2});

    switch_user $user2;
    $has_view = grep { $_->name eq 'FooBar3' } @{$views->user_views_all};
    ok($has_view, "Admin user can create view as other user");

    # Edit other user's view
    switch_user $user_admin;
    $view5->view_update({name => 'FooBar4'});

    switch_user $user2;
    my $view5b = grep $_->name eq 'FooBar4', @{$views->user_views_all};
    is $view5b, $view5, "Admin user updated other user's view";
}

# Check that view can be deleted, with alerts

my $view6 = $views->view_create({name => 'view6'});
$view6->alert_create({frequency => 24});

my $view_count1 = @{$sheet->all_views};
$view6->delete;
my $view_count2 = @{$sheet->all_views};
cmp_ok $view_count2, '==', $view_count1 - 1, "View deleted successfully";

# Try and load a view with an invalid column in the filter (e.g. deleted)
my $filter = Linkspace::Filter->from_hash({
    rules => [
        {
            id       => 100,
            type     => 'string',
            value    => 'foo2',
            operator => 'equal',
        },
    ],
    condition => 'equal',
});

switch_user $user_admin;
my $view7b = $views->view_create({ name => 'Test', filter => $filter});
ok !defined $view7b;
like($@, qr/does not exist/, "Sensible error message for invalid field ID");

# Force it into database (as if field deleted since view written)
my $view7 = $views->view_create({ filter => $filter });

# Check the invalid column as been removed for the base64 representation going
# to the template.
# Need to compare as hash to ensure consistency
my $hash = {rules => [{}], condition => 'equal'};
is_deeply decode_json(decode_base64($view7->filter->base64)), $hash,
    "Invalid rule removed from base64 of filter";

# Check view names that are too long for the DB
my $long = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum';

try { $views->view_create({ name => $long }) }
like $@, qr/View name must be less than/, "Failed to create view with name too long";

done_testing;
