use Test::More; # tests => 1;
use strict;
use warnings;

use JSON qw(encode_json);
use Log::Report;
use GADS::Filter;
use GADS::Group;
use GADS::Groups;
use Linkspace::Layout;
use GADS::Record;
use GADS::Records;
use GADS::Schema;

use t::lib::DataSheet;

# 2 sets of data to alternate between for changes
my $data = {
    a => [
        {
            string1    => 'foo',
            integer1   => '100',
            enum1      => 7,
            tree1      => 10,
            date1      => '2010-10-10',
            daterange1 => ['2000-10-10', '2001-10-10'],
            curval1    => 1,
        },
    ],
    b => [
        {
            string1    => 'bar',
            integer1   => '200',
            enum1      => 8,
            tree1      => 11,
            date1      => '2011-10-10',
            daterange1 => ['2000-11-11', '2001-11-11'],
            curval1    => 2,
        },
    ],
};

my $curval_sheet = t::lib::DataSheet->new(instance_id => 2, no_groups => 1, users_to_create => [qw/superadmin/]);
$curval_sheet->create_records;
my $schema  = $curval_sheet->schema;
my $sheet   = t::lib::DataSheet->new(data => $data->{a}, schema => $schema, curval => 2, no_groups => 1, users_to_create => [qw/superadmin/]);
my $layout  = $sheet->layout;
my $columns = $sheet->columns;
$sheet->create_records;

# Create users
my %users = (
    read      => $sheet->create_user,
    limited   => $sheet->create_user,
    readwrite => $sheet->create_user,
);

# Groups
foreach my $group_name (qw/read limited readwrite/)
{
    my $group  = GADS::Group->new(schema => $schema);
    $group->name($group_name);
    $group->write;
}

# Check groups and add users
my $groups = GADS::Groups->new(schema => $schema);
is( scalar @{$groups->all}, 3, "Groups created successfully");
my %groups;
foreach my $group (@{$groups->all})
{
    my $usero = $users{$group->name};
    $usero->groups($schema->resultset('User')->find($sheet->user->id), [$group->id]);
    $groups{$group->name} = $group->id;
}

# Should be 3 groups rows now
is( $schema->resultset('UserGroup')->count, 3, "Correct number of permissions added");

# Write groups such that the limited group only has read/write access to one
# field in the main sheet, but not the curval sheet
foreach my $column ($layout->all(exclude_internal => 1), $curval_sheet->layout->all(exclude_internal => 1))
{
    # Read only
    my $read = [qw/read/];
    my $all  = [qw/read write_new write_existing approve_new approve_existing
        write_new_no_approval write_existing_no_approval
    /];
    my $permissions = {
        $groups{read} => $read,
    };
    $permissions->{$groups{limited}} = $all
        if $column->name eq 'string1' && $column->layout->instance_id != $curval_sheet->instance_id;
    $permissions->{$groups{readwrite}} = $all;
    $column->set_permissions($permissions);
    $column->write;
}
# Turn off the permission override on the curval sheet so that permissions are
# actually tested (turned on initially to populate records)
$curval_sheet->layout->user_permission_override(0);

foreach my $user_type (qw/readwrite read limited/)
{
    my $user = $users{$user_type};
    # Need to build layout each time, to get user permissions
    # correct
    my $layout = Linkspace::Layout->new(
        user        => $user,
        schema      => $schema,
        config      => GADS::Config->instance,
        instance_id => $sheet->instance_id,
    );
    my $layout_curval = Linkspace::Layout->new(
        user        => $user,
        schema      => $schema,
        config      => GADS::Config->instance,
        instance_id => $curval_sheet->instance_id,
    );

    # Check overall layout permissions. Having all the columns built in a
    # layout will affect how permissions are checked, so test both
    foreach my $with_columns (0..1)
    {
        if ($with_columns)
        {
            $layout->columns;
            $layout_curval->columns;
        }

        if ($user_type eq 'read')
        {
            ok(!$layout->user_can('write_existing'), "User $user_type cannot write to anything");
        }
        else
        {   ok($layout->user_can('write_existing'), "User $user_type can write to something in layout");
        }
        if ($user_type eq 'readwrite')
        {
            ok($layout_curval->user_can('write_existing'), "User $user_type can write to something in layout");
        }
        else {
            ok(!$layout_curval->user_can('write_existing'), "User $user_type cannot write to anything");
        }
        $layout->clear;
        $layout_curval->clear;
    }

    # Check that user has access to all curval values
    my $curval_column = $columns->{curval1};
    is( @{$curval_column->filtered_values}, 2, "User has access to all curval values (filtered)" );
    is( @{$curval_column->all_values}, 2, "User has access to all curval values (all)" );

    # Now apply a filter. Correct number of curval values should be
    # retrieved, regardless of user perms
    $curval_column->filter(GADS::Filter->new(
        as_hash => {
            rules => [{
                id       => $curval_sheet->columns->{string1}->id,
                type     => 'string',
                value    => 'Foo',
                operator => 'equal',
            }],
        },
        layout => $layout,
    ));
    $curval_column->write;

    cmp_ok @{$curval_column->filtered_values}, '==', 1,
        "User has access to all curval values after filter";

    # Reset for next test
    $curval_column->clear_filter;
    $curval_column->write;


    # First try writing to existing record
    my $sheet7 = make_sheet '7', rows => 1;

    my $row7_2 = $sheet7->add_row({});

...
    foreach my $rec (@records)
    {
        _set_data($data->{b}->[0], $layout, $rec, $user_type);
        my $record_max = $schema->resultset('Record')->get_column('id')->max;
        try { $rec->write(no_alerts => 1) };
        if ($user_type eq 'read')
        {
            ok( $@, "Write failed to read-only user" );
        }
        else
        {   ok( !$@, "Write for user with write access did not bork" );
            my $record_max_new = $schema->resultset('Record')->get_column('id')->max;
            is( $record_max_new, $record_max + 1, "Change in record's values took place for user $user_type" );
            # Reset values to previous
            _set_data($data->{a}->[0], $layout, $rec, $user_type);
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
    my $sheet   = test_sheet
    my $columns = $sheet->columns;
    my $group1  = $sheet->group;    #XXX overridden version
    my $string1 = $columns->{string1};
    $sheet->create_records;

    $string1->set_permissions($group1 => [qw/read write_new write_existing/]);
    $string1->set_permissions($group2 => [qw/read write_new write_existing/]);

    my $rules = Linkspace::Filter->from_hash({
        rules     => [{
            id       => $string1->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'equal',
        }],
    });

    my $view = $sheet->view_create({
        name        => 'Foo',
        filter      => $rules,
        columns     => [ $string1->id ],
        owner       => undef,
    );
    $view->write;

    $view->alert_create({ frequency => 24 });
    my $filter = $view->filter_json;
    like $filter, qr/Foo/, "Filter initially contains Foo search";

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
    my $sheet = t::lib::DataSheet->new(site_id => 1);
    $sheet->create_records;
    my $schema = $sheet->schema;
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
            ok($user, "Superadmin user created successfully");
            ok(!$failed, "Creating superadmin user did not bork");
        }
        else {
            ok(!$user, "Superadmin user not created as $usertype");
            like($failed, qr/do not have permission/, "Creating superadmin user borked as $usertype");
        }
    }
}

done_testing();

sub _set_data
{   my ($data, $layout, $rec, $user_type) = @_;
    foreach my $column ($layout->all(userinput => 1))
    {
        next if $user_type eq 'limited' && $column->name ne 'string1';
        my $datum = $rec->fields->{$column->id};
        $datum->set_value($data->{$column->name});
    }
}
