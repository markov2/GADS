use Linkspace::Test
    create_test_session => 0;

# 2 sets of data to alternate between for changes

sub _set_data($$$);

my $row_a = {
    string1    => 'foo',
    integer1   => '100',
    enum1      => 7,
    tree1      => 10,
    date1      => '2010-10-10',
    daterange1 => ['2000-10-10', '2001-10-10'],
    curval1    => 1,
};

my $row_b = {
    string1    => 'bar',
    integer1   => '200',
    enum1      => 8,
    tree1      => 11,
    date1      => '2011-10-10',
    daterange1 => ['2000-11-11', '2001-11-11'],
    curval1    => 2,
};

my $curval_sheet = make_sheet 2,
    no_groups       => 1,
    users_to_create => [ qw/superadmin/ ];

my $sheet   = make_sheet 1,
    rows         => [ $row_a ],
    curval_sheet => $curval_sheet,
    no_groups    => 1,
    users_to_create => [ qw/superadmin/ ];

my $layout  = $sheet->layout;

# Create users
my %users = (
    read      => $sheet->create_user,
    limited   => $sheet->create_user,
    readwrite => $sheet->create_user,
);

### Create groups

$site->groups->group_create( { name => $_ } )
    for qw/read limited readwrite/;

### Check groups and add users

my $all_groups = $site->groups->all_groups;
cmp_ok @$all_groups, '==', 3, "Groups created successfully";

my %groups;
foreach my $group (@$all_groups)
{   my $usero = $users{$group->name};
    $usero->groups($schema->resultset('User')->find($sheet->user->id), [$group->id]);
    $groups{$group->name} = $group->id;
}

# Should be 3 groups rows now
is( $schema->resultset('UserGroup')->count, 3, "Correct number of permissions added");

# Write groups such that the limited group only has read/write access to one
# field in the main sheet, but not the curval sheet

my @all_perms = qw/read write_new write_existing approve_new approve_existing
    write_new_no_approval write_existing_no_approval/;

foreach my $column ($layout->column_search(exclude_internal => 1),
                    $curval_sheet->layout->column_search(exclude_internal => 1))
{
    # Read only
    my $permissions = { $groups{read} => [ 'read' ] };

    $permissions->{$groups{limited}} = \@all_perms
        if $column->name eq 'string1'
        && $column->sheet_id != $curval_sheet->id;

    $permissions->{$groups{readwrite}} = \@all_perms;

    $layout->column_update($column, { permissions => $permissions };
}

# Turn off the permission override on the curval sheet so that permissions are
# actually tested (turned on initially to populate records)

$user->permission_overide(0); #XXX

foreach my $user_type (qw/readwrite read limited/)
{
    my $user = $users{$user_type};

#XXX no
    # Need to build layout each time, to get user permissions
    # correct
    my $layout = Linkspace::Layout->new(
        user        => $user,
        schema      => $schema,
        config      => GADS::Config->instance,
        instance_id => $sheet->instance_id,
    );

    my $curval_layout = Linkspace::Layout->new(
        user        => $user,
        schema      => $schema,
        config      => GADS::Config->instance,
        instance_id => $curval_sheet->instance_id,
    );

    # Check overall layout permissions. Having all the columns built in a
    # layout will affect how permissions are checked, so test both
    foreach my $with_columns (0..1)
    {
        if ($user_type eq 'read')
        {
            ok(!$layout->user_can('write_existing'), "User $user_type cannot write to anything");
        }
        else
        {   ok($layout->user_can('write_existing'), "User $user_type can write to something in layout");
        }

        if ($user_type eq 'readwrite')
        {
            ok($curval_layout->user_can('write_existing'), "User $user_type can write to something in layout");
        }
        else
        {   ok(!$curval_layout->user_can('write_existing'), "User $user_type cannot write to anything");
        }
    }

    # Check that user has access to all curval values
    my $curval_column = $columns->{curval1};
    is( @{$curval_column->filtered_values}, 2, "User has access to all curval values (filtered)" );
    is( @{$curval_column->all_values}, 2, "User has access to all curval values (all)" );

    # Now apply a filter. Correct number of curval values should be
    # retrieved, regardless of user perms
    $layout->column_update($curval_column => { filter => { rules => {
        column   => $curval_layout->column('string1'),
        type     => 'string',
        value    => 'Foo',
        operator => 'equal',
    }}});

    cmp_ok @{$curval_column->filtered_values}, '==', 1,
        "User has access to all curval values after filter";

    # First try writing to existing record
    my $sheet7 = make_sheet 7;

    my $row7_2 = $sheet7->content->row_create;

...
    foreach my $rec (@records)
    {
        _set_data($row_b, $rec, $user_type);
        my $record_max = $schema->resultset('Record')->get_column('id')->max;
        try { $rec->write(no_alerts => 1) };
        if ($user_type eq 'read')
        {   ok $@, "Write failed to read-only user";
        }
        else
        {   ok( !$@, "Write for user with write access did not bork" );
            my $record_max_new = $schema->resultset('Record')->get_column('id')->max;
            is( $record_max_new, $record_max + 1, "Change in record's values took place for user $user_type" );
            # Reset values to previous
            _set_data($row_a, $rec, $user_type);
            $rec->write(no_alerts => 1);
        }
    }

    # Delete created record unless one shouldn't have been created (read only test)
    unless ($user_type eq 'read')
    {   $row7_2->delete;
        $row7_2->purge;

        my $page = $sheet->content->search;
        cmp_ok $page->row_count, '==', 1, "Row purged correctly";
    }
}

# Check deletion of read permissions also updates dependent values
my $group2 = make_group '2';

foreach my $test (qw/single all/)
{
    my $sheet   = make_sheet 1;
    my $group1  = $sheet->group;    #XXX overridden version??>

    $sheet->layout->column_update(string1 => { permissions => [
        $group1 => [qw/read write_new write_existing/],
        $group2 => [qw/read write_new write_existing/],
    ]});

    my $rules = { rule => {
        id       => 'string1',
        operator => 'equal',
        value    => 'Foo',
    }};

    my $view = $sheet->views->view_create({
        name        => 'Foo',
        filter      => $rules,
        columns     => [ 'string1' ],
        owner       => undef,
    );

    $view->alert_create({ frequency => 24 });

    like $view->filter_json, qr/Foo/, "Filter initially contains Foo search";

    my $cached1 = $view->alerts_cached_for($string1);
    ok @$cached1, "Alert cache contains string1 column";

    my $monitors1 = $view->monitors_on_column($string1);
    cmp_ok @$monitors1, '==', 1, "String column initially in view";

    # Start by always keeping one set of permissions
    $string1->set_permissions($group1, [qw/read write_new write_existing/]);

    # Add second set if required
    $string1->set_permissions($group2, [qw/write_new write_existing/])
        if $test eq 'single';

    my $monitors2 = $view->monitors_on_column($string1);
    cmp_ok @$monitors2, '==', 1,  "View still has column with read access remaining";

    my $filter2 = $view->filter_json;
    like $filter2, qr/Foo/, "Filter still contains Foo search";

    my $cached2 = $view->alerts_cached_for($string1);
    ok @$cached2, "Alert cache still contains string1 column";

$layout->clear;

    # Now remove read from all groups
    $string1->remove_all_permissions;
    $string1->set_permissions($group2 => [qw/write_new write_existing/])
        if $test ne 'all';

    my $monitors3 = $view->monitors_on_column($string1);
    cmp_ok @$monitors3, '==', 0,
         "String column removed from view when permissions removed";

    my $filter3 = $view->filter_json;
    unlike $filter3, qr/Foo/, "Filter no longer contains Foo search";

    my $cached3 = $view->alerts_cached_for($string1);
    ok ! @$cached3, "Alert cache no longer contains string1 column";
}

# Check setting of global permissions - can only be done by superadmin
{
    my $sheet = make_site 1;

    foreach my $usertype (qw/user user_useradmin user_normal1/) # "user" is superadmin
    {
        my $user;
        try {
            $user = $schema->resultset('User')->create_user(
                current_user     => $sheet->$usertype,
                username         => "$usertype\@example.com",
                email            => "$usertype\@example.com",
                firstname        => 'Joe',
                surname          => 'Bloggs',
                no_welcome_email => 1,
                permissions      => [qw/superadmin/],
            );
        };
        my $failed = $@;
        if ($usertype eq 'user')
        {
            ok $user, "Superadmin user created successfully";
            ok !$failed, "Creating superadmin user did not bork";
        }
        else
        {   ok !$user, "Superadmin user not created as $usertype";
            like $failed, qr/do not have permission/, "Creating superadmin user borked as $usertype";
        }
    }
}

done_testing;

sub _set_data($$$)
{   my ($data, $row, $user_type) = @_;

    my %data = $data;
    delete $data{string1} if $user_type eq 'limited';

    $row->revision_create($data);
}
