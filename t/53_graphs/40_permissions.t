# Was test t/012_graph_permissions.t and
# partially extracted into t/320_users/201_groups_viewable.t

use Linkspace::Test
    not_ready => 'needs support for graphs';

my $site   = test_site;
my $sheet  = test_sheet with_columns => 1;

my $owner  = $sheet->owner;
my $graphs = $sheet->graphs;
my $layout = $sheet->layout;

my $user1 = test_user;
my $user2 = make_user '2';

my $group1 = $sheet->group;

# Add first normal user to second group
my $group2 = $site->groups->group_create({name => 'group2'});
$group2->add_user($user1);

ok   $user1->is_in_group($sheet->group);
ok   $user1->is_in_group($group2);
ok   $user2->is_in_group($sheet->group);
ok ! $user2->is_in_group($group2);

ok ! @{$graphs->all_graphs}, 'No graphs created yet';

my %graph_template = (
    title        => 'Test',
    type         => 'bar',
    x_axis       => $layout->column('string1'),
    y_axis       => $layout->column('enum1'),
    y_axis_stack => 'count',
);

### Create all users shared graph by owner

$::session->login($owner);

$graphs->graph_create({
    %graph_template,
    is_shared    => 1,
});

cmp_ok scalar @{$graphs->all_graphs}, '==', 1, 'Owner created graph';

sub _graph_count { my $user = shift; scalar @{$graphs->user_graphs($user)} }
is _graph_count($user1), 1, "Normal user can see graph";

### Create personal graph by owner

$graphs->graph_create({
    %graph_template,
    is_shared    => 0,
});
is _graph_count($user1), 1, "Normal user can see same graphs";

# Create shared group graph by owner
$graphs->graph_create({
    %graph_template,
    is_shared    => 1,
    group        => $group2,
});

is _graph_count($user1), 2, "First user can see shared graph";
is _graph_count($user2), 1, "Second user cannot";

# Attempt to create shared graph by first user
$::session->login($user1);

try {
    $graphs->graph_create({
        %graph_template,
        is_shared    => 1,
        group        => $group1,
    });
};
like $@, qr/do not have permission/,
    "Unable to create shared graph as normal user";

# Add group graph creation to normal user and try again
$sheet->group_allow($group1, 'view_group');

$graphs->graph_create({
    %graph_template,
    is_shared    => 1,
    group        => $group1,
});

$sheet->sheet_change({ owner => $user2 });

cmp_ok _graph_count($user1), '==', 2, "Normal user can see other user shared graph";

# Try creating all user shared graph

$graphs->graph_create({
   %graph_template,
   is_shared    => 1,
});

like $@, qr/do not have permission/,
    "Unable to create all user shared graph as group user";

done_testing();

