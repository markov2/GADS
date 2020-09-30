
use Linkspace::Test;

use JSON qw(encode_json);

set_fixed_time '10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S';

# A bunch of records that will be used for the alert tests - mainly different
# records for different tests. XXX There needs to be a better way of managing
# these - each are referred to by their IDs in the tests, which makes adding
# tests difficult
my $data = [
    {
        string1    => '',
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },
    {
        string1    => '',
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },
    {
        string1    => '',
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },
    {
        string1    => '',
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },
    {
        string1    => 'Foo',
        date1      => '2014-10-10',
        daterange1 => ['2010-01-04', '2011-06-03'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },
    {
        string1    => 'FooBar',
        date1      => '2015-10-10',
        daterange1 => ['2009-01-04', '2017-06-03'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 2,
    },
    {
        string1    => 'FooBar',
        date1      => '2015-10-10',
        daterange1 => ['2009-01-04', '2017-06-03'],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 2,
    },
    {
        string1    => 'FooBar',
        date1      => '2015-10-10',
        daterange1 => ['2009-01-04', '2017-06-03'],
        enum1      => 'foo1',
        tree1      => 'tree1',
    },
    {
        string1    => 'Disappear',
    },
    {
        string1    => 'FooFooBar',
        date1      => '2010-10-10',
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        daterange1 => ['2009-01-04', '2017-06-03'],
    },
    {
        curval1    => 1,
        daterange1 => ['2014-01-04', '2017-06-03'],
    },
    {
        curval1    => 1,
        daterange1 => ['2014-01-04', '2017-06-03'],
    },
];

my $curval_sheet = make_sheet '2', calc_return_type => 'string';
$curval_sheet->create_records;
my $curval_columns = $curval_sheet->columns;

my $sheet = make_sheet '3',
    rows         => $data,
    curval_sheet => $curval_sheet;

my $autocur1 = $curval_sheet->layout->column_create({
    curval_columns  => [ 'daterange' ],
    refers_to_sheet => $sheet,
    related_column  => [ 'curval1' ],
);

my $curval_calc = $curval_sheet->layout->column('calc1');
$curval_calc->code("
    function evaluate (L2autocur1)
        return_value = ''
        for _, v in pairs(L2autocur1) do
            if v.field_values.L1daterange1.from.year == 2014 then
                return_value = return_value .. v.field_values.L1daterange1.from.year
            end
        end
        return return_value
    end
");

my $created_calc = $sheet->layout->column_create({
    name        => "Created calc",
    return_type => 'date',
    code        => "
        function evaluate (_created)
            return _created.epoch
        end
    ",
    permissions => { $sheet->group => $sheet->default_permissions },
});

my @filters = (
    {
        name       => 'Calc with record created date',
        rules      => undef,
        columns    => [ $created_calc ],
        current_id => 3,
        update     => [ { column => 'string1', value=> 'foobar' } ],
        alerts     => 1,
    },
    {
        name       => 'View filtering on record created date',
        rules      => [ {
            column   => '_created',
            type     => 'string',
            operator => 'greater',
            value    => '2014-10-20',
        } ],
        columns    => [ 'string1' ],
        current_id => 4,
        update     => [ { column => 'string1', value => 'FooFoo' } ],
        alerts     => 1, # New record only
    },
    {
        name       => 'View filtering on record updated date',
        rules      => [ {
            column   => '_version_datetime',
            type     => 'string',
            operator => 'greater',
            value    => '2014-10-20',
        } ],
        columns    => [ 'date1' ], # No change to data shown
        current_id => 5,
        update     => [ {
            column    => 'string1',
            value     => 'FooFoo2',
        } ],
        alerts     => 2, # New record and updated record
    },
    {
        name       => 'View filtering on record updated person',
        rules      => [ {
            id       => $layout->column('_version_user')->id,
            type     => 'string',
            value    => 'User5, User5',
            operator => 'equal',
        } ],
        columns    => [ $columns->{date1}->id ], # No change to data shown
        current_id => 6,
        update     => [ {
            column   => 'string1',
            value    => 'FooFoo3',
        } ],
        alerts     => 2, # New record and updated record
    },
    {
        name       => 'View filtering on record updated person - unchanged',
        rules      => [ {
            id       => $layout->column_by_name_short('_version_user')->id,
            type     => 'string',
            value    => 'User5, User5',
            operator => 'equal',
        } ],
        columns   => [$columns->{date1}->id], # No change to data shown
        # Use same record as previous test - user making the update will not
        # have changed and therefore this should not alert except for the new
        # record
        current_id => 6,
        update     => [ {
            column   => 'string1',
            value    => 'FooFoo4',
        } ],
        alerts     => 1, # New record only
    },
    {
        name       => 'Update of record in no filter view',
        rules      => undef,
        columns    => [], # No columns, only appearance of new record will matter
        current_id => 3,
        update     => [ {
            column   => 'string1',
            value    => 'xyz',
        } ],
        alerts     => 1,
    },
    {
        name       => 'Record appears in view',
        rules      => [ {
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'Nothing to see here',
            operator => 'equal',
        }],
        columns    => [$columns->{string1}->id],
        current_id => 3,
        update     => [ {
            column   => 'string1',
            value    => 'Nothing to see here',
        } ],
        alerts     => 2, # new record and updated record
    },
    {
        name       => 'Global view',
        rules      => [{
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'Nothing to see here2',
            operator => 'equal',
        }],
        columns => [$columns->{string1}->id],
        current_id => 3,
        update     => [ {
            column => 'string1',
            value  => 'Nothing to see here2',
        } ],
        alerts     => 2, # new record and updated record
        is_global_view => 1,
    },
    {
        name  => 'Group view',
        rules => [ {
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'Nothing to see here3',
            operator => 'equal',
        } ],
        columns    => [ $columns->{string1}->id ],
        current_id => 3,
        update     => [ {
            column   => 'string1',
            value    => 'Nothing to see here3',
        } ],
        alerts     => 2, # new record and updated record
        is_group_view => 1,
    },
    {
        name  => 'Update to row in view',
        rules => [
            {   id       => $columns->{string1}->id,
                type     => 'string',
                value    => 'Foo',
                operator => 'equal',
            },
            {
                id       => $columns->{date1}->id,
                type     => 'date',
                value    => '2000-01-04',
                operator => 'greater',
            },
        ],
        columns    => [ $columns->{date1}->id ],
        current_id => 7,
        update     => [
            {
                column => 'date1',
                value  => '2014-10-15',
            },
            {
                column => 'string1',
                value  => 'Foo',
            },
        ],
        alerts     => 2, # New record and updated record
    },
    {
        name       => 'Update to row not in view',
        rules      => [ {
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'FooBar',
            operator => 'equal',
        } ],
        columns    => [ $columns->{string1}->id ],
        current_id => 8,
        update     => [ {
            column   => 'date1',
            value    => '2014-10-15',
        } ],
        alerts     => 0, # Neither update nor new appear/change in view
    },
    {
        name       => 'Update to row, one column in view and one not',
        rules      => [ {
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'FooBar',
            operator => 'begins_with',
        } ],
        columns    => [ $columns->{string1}->id ],
        current_id => 9,
        update     => [
            {
                column => 'string1',
                value  => 'FooBar2',
            },
            {
                column => 'date1',
                value  => '2017-10-15',
            },
        ],
        alerts      => 2, # One alert for only single column in view, one for new record
    },
    {
        name       => 'Update to row, changes to 2 columns both in view',
        rules      => [ {
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'FooBar',
            operator => 'begins_with',
        } ],
        columns    => [ $columns->{string1}->id, $columns->{date1}->id ],
        current_id => 10,
        update     => [
            {
                column => 'string1',
                value  => 'FooBar2',
            },
            {
                column => 'date1',
                value  => '2017-10-15',
            },
        ],
        # One alert for only single column in view, one for new record
        alerts     => 3,
    },
    {
        name       => 'Disappears from view',
        rules      => [{
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'Disappear',
            operator => 'equal',
        }],
        columns    => [ $columns->{string1}->id ],
        current_id => 11,
        update     => [ {
            column   => 'string1',
            value    => 'Gone',
        } ],
        alerts     => 1, # Disappears
    },
    {
        name       => 'Change of filter of column not in view',
        rules      => [{
            id       => $columns->{string1}->id,
            type     => 'string',
            value    => 'FooFooBar',
            operator => 'equal',
        }],
        columns    => [$columns->{date1}->id],
        current_id => 12,
        update     => [ {
            column   => 'string1',
            value    => 'Gone',
        } ],
        alerts     => 1, # Disappears
    },
    {
        name       => 'Change of calc field in view',
        rules      => undef,
        columns    => [ $columns->{calc1}->id ],
        current_id => 13,
        update     => [ {
            column => 'daterange1',
            value  => ['2010-10-10', '2011-10-10'],
        } ],
        alerts     => 2, # New record plus Calc field updated
    },
    {
        name       => 'Change of calc field forces record into view',
        rules      => [{
            id       => $columns->{calc1}->id,
            type     => 'string',
            value    => '2014',
            operator => 'equal',
        }],
        columns    => [$columns->{calc1}->id],
        current_id => 14,
        update => [ {
            column   => 'daterange1',
            value    => ['2014-10-10', '2015-10-10'],
        } ],
        alerts     => 2, # New record plus calc field coming into view
    },
    {
        name  => 'Change of calc field makes no change to record not in view',
        rules => [{
            id       => $columns->{calc1}->id,
            type     => 'string',
            value    => '2015',
            operator => 'equal',
        }],
        columns => [$columns->{calc1}->id],
        current_id => 15,
        update => [
            {
                column => 'daterange1',
                value  => ['2014-10-10', '2015-10-10'],
            },
        ],
        alerts => 0, # Neither new record nor changed record will be in view
    },
    {
        name  => 'Change of rag field in view',
        rules => undef,
        columns => [$columns->{rag1}->id],
        current_id => 16,
        update => [
            {
                column => 'daterange1',
                value  => ['2012-10-10', '2013-10-10'],
            },
        ],
        alerts => 2, # New record plus Calc field updated
    },
    {
        name  => 'Change of rag field forces record into view',
        rules => [{
            id       => $columns->{rag1}->id,
            type     => 'string',
            value    => 'c_amber',
            operator => 'equal',
        }],
        columns => [$columns->{rag1}->id],
        current_id => 17,
        update => [
            {
                column => 'daterange1',
                value  => ['2012-10-10', '2015-10-10'],
            },
        ],
        alerts => 2, # New record plus calc field coming into view
    },
    {
        name  => 'Change of rag field makes no difference to record not in view',
        rules => [{
            id       => $columns->{rag1}->id,
            type     => 'string',
            value    => 'c_amber',
            operator => 'equal',
        }],
        columns => [$columns->{rag1}->id],
        current_id => 18,
        update => [
            {
                column => 'daterange1',
                value  => ['2013-10-10', '2015-10-10'],
            },
        ],
        alerts => 0, # Neither new record nor existing record in view
    },
    {
        name  => 'Change of autocur/calc in other table as a result of curval change',
        rules => [{
            id       => $curval_columns->{calc1}->id,
            type     => 'string',
            value    => '2014',
            operator => 'contains',
        }],
        alert_sheet      => $curval_sheet,
        columns          => [$curval_columns->{calc1}->id],
        current_id       => 19,
        alert_current_id => 2,
        update => [
            { column => 'curval1', value  => 2 },
            { column => 'daterange1', value  => ['2014-01-04', '2017-06-03'] },
        ],
        # One when new instance1 record means that 2014 appears in the autocur,
        # then a second alert when the existing instance1 record is edited and
        # causes it also to appear in the autocur
        alerts => 2,
    },
    {
        name  => 'Change of autocur in other table as a result of curval change',
        alert_sheet => $curval_sheet,
        columns    => [ $autocur1 ],
        current_id => 20,
        alert_current_id => 2,
        update     => [
            { column => 'curval1', value  => 2 },
            { column => 'daterange1', value  => ['2014-01-04', '2017-06-03'] },
        ],
        # There are actually 2 changes that take place that will cause alerts,
        # but both are exactly the same so only one will be written to the
        # alert cache.  The addition of a new record with "2" as the curval
        # value will cause a change of current ID 2, and then the change of an
        # existing record to value "2" will cause another similar change.
        alerts => 1,
    },
    {
        name  => 'Change of curval sub-field in filter',
        rules => [{
            id       => $columns->{curval1}->id . '_' . $curval_columns->{string1}->id,
            type     => 'string',
            value    => 'Bar',
            operator => 'equal',
        }],
        columns    => [ 'string1' ],
        current_id => 1,
        alert_current_id => [3,4,5,6,7,19,20],
        update_layout    => $curval_sheet->layout,
        update     => [ { column => 'string1', value => 'Bar' } ],
        # 7 new records appear in the view, which are the 7 records referencing
        # curval record ID 1, none of which were contained in the view, and
        # then all appear when the curval record is updated to include it in
        # that view
        alerts     => 7,
    },
);

# First write all the filters and alerts
foreach my $filter (@filters)
{
    my $rules = $filter->{rules} ? {
        rules     => $filter->{rules},
        condition => $filter->{condition},
    } : {};

    my %view = (
        name        => $filter->{name},
        filter      => $rules,
        columns     => $sheet->layout->columns($filter->{columns}),
    );

    $view{is_global} = 1
        if $filter->{is_global_view} || $filter->{is_group_view};

    $view{group} = $sheet->group if $filter->{is_group_view};

    my $in_sheet = $filter->{alert_sheet} || $sheet;
    my $view = $in_sheet->views->view_create(\%view);

    my $alert = $view->alert_set(24, $user2); # Different user to that doing the update
    $filter->{alert_id} = $alert->id;
}

$ENV{GADS_NO_FORK} = 1;  #XXX

set_fixed_time('11/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

# Now update all the values, checking alerts as we go
foreach my $filter (@filters)
{
    # Clear out any existing alerts, for a fair count and also in case the same
    # alert is written again
    $::db->delete(AlertSend => {
        current_id => $filter->{alert_current_id} || $filter->{current_id},
        alert_id   => $filter->{alert_id},
    });

    # First add record
    my $update_layout = $filter->{update_layout} || $layout;
    my $record = GADS::Record->new(
        user     => $sheet->user_normal2,
        layout   => $update_layout,
    );
    $record->initialise;

    foreach my $datum (@{$filter->{update}})
    {   my $col_id = $update_layout->column($datum->{column})->id;
        $record->field($col_id)->set_value($datum->{value});
    }
    $record->write;

    my $alert_finish; # Count for written alerts
    # Count number of alerts for the just-written record, but not for
    # autocur tests (new record will affect other record)
    $alert_finish += $::db->search(AlertSend =>{
        current_id => $record->current_id,
        alert_id   => $filter->{alert_id},
    })->count unless $filter->{alert_current_id};

    # Now update existing record
    $record->clear;
    $record->find_current_id($filter->{current_id});

    foreach my $datum (@{$filter->{update}})
    {   my $col_id = $update_layout->column($datum->{column})->id;
        $record->fields->{$col_id}->set_value($datum->{value});
    }
    $record->write;

    # Add the number of alerts created as a result of record update to previous
    # alert count
    $alert_finish += $schema->resultset('AlertSend')->search({
        current_id => $filter->{alert_current_id} || $filter->{current_id},
        alert_id   => $filter->{alert_id},
    })->count;

    # Number of new alerts is the change of values, plus the new record, plus the view without a filter
    is( $alert_finish, $filter->{alerts}, "Correct number of alerts queued to be sent for filter: $filter->{name}" );
}

# Test updates of views
$data = [
    {
        string1 => 'Foo',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Foo',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Foo',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Foo',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Foo',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Bar',
        date1   => '2014-10-10',
    },
    {
        string1 => 'Bar',
        date1   => '2014-10-10',
    },
];

sub _in_alert_cache($;$)
{   my $view = shift;
    my %search = (view_id => $view);
    $search{user_id} = blessed $_[0] ? $_[0]->id : $_[0];
    $::db->resultset(AlertCache => \%search)->count;
}

sub _in_alert_send($)
{   my $view = shift;
    $::db->resultset(AlertSend => {view_id => $view->id})->count;
}

$sheet = make_sheet 1, rows => $data;

# First create a view with no filter
my $view = $views->view_create({
    name        => 'view1',
    columns     => [ 'date1' ],
});

my $alert1 = $view1->create_alert(24, $sheet->user);

cmp_ok _in_alert_cache($view1), '==',  7,
    'Correct number of alerts inserted';

# Add a column, check alert cache
$views->view_update($view1, { columns => [ 'string1', 'date1' ] });

cmp_ok _in_alert_cache($view1), '==', 14, 
    'Correct number of alerts for column addition';

# Remove a column, check alert cache

$views->view_update($view1, { columns => [ 'string1' ] });
cmp_ok _in_alert_cache, '==',  7,
   'Correct number of alerts for column removal';

# Add a filter to the view, alert cache should be updated
$views->view_update($view1 => { filter => { rule => {
        column   => 'string1',
        type     => 'string',
        value    => 'Foo',
        operator => 'equal',
}}});

cmp_ok _in_alert_cache($view1), '==', 5,
    'Correct number of alerts after view updated';

# Instantiate view from scratch, check that change in filter changes alerts
# First as hash

my $filter2 = { rule => { columns  => 'string1',
    type     => 'string',
    operator => 'equal',
    value    => 'Bar',
}};

my $view2 = $views->view_create({ filter => $filter2 });

cmp_ok _in_alert_cache($view2), '==', 2,
    'Correct number of alerts after view updated (from hash)';

my $filter3 = { rule => {
    column   => 'string1',
    type     => 'string',
    operator => 'equal',
    value    => 'Foo',
}};

my $view3 = $views->view_create({ filter => $filter3 });

cmp_ok _in_alert_cache($view3), '==', 3,
    'Correct number of alerts after view updated (from json)';


my $user1 = make_user '1';
my $user4 = make_user '4';


# Do some tests on CURUSER alerts. One for filter on person field, other on string

    # Hard-coded user IDs. Ideally we would take these from the users that have
    # been created, but they need to be defined now to pass to the datasheet
    # creation
my @curuser_person_data = (
    { string1 => 'Foo', person1 => $user1 },
    { string1 => 'Bar', person1 => $user1 },
    { string1 => 'Foo', person1 => $user4 },
    { string1 => 'Foo', person1 => undef  },
    { string1 => 'Bar', person1 => undef  },
);
test_curuser 'person', \@person_data, 'person1';

my @curuser_string_data = (
   { integer1 => '100', string1 => 'User1, User1' },
   { integer1 => '200', string1 => 'User1, User1' },
   { integer1 => '100', string1 => 'User4, User4' },
   { integer1 => '100', string1 => undef },
   { integer1 => '200', string1 => undef },
);
test_curuser 'string', \@curuser_string_data, 'string1';


sub test_curuser
{   my ($curuser_type, $data, $filter_col ) = @_;

    $sheet = make_sheet 1, rows => $data;

    # First create a view with no filter
    my $col_ids = $curuser_type eq 'person'
      ? [ 'string1',  'person1' ]
      : [ 'integer1', 'string1' ];

    # Add a person filter, check alert cache
    my $filter1 = { rules  => {
        columns  => $filter_col,
        type     => 'string',
        operator => 'equal',
        value    => '[CURUSER]',
    }};

    my $view1 = $views->view_create({
        name        => 'view1',
        is_global   => 1,
        columns     => $col_ids,
        filter      => $filter1,
    });

    $view1->alert_set(24, $user2);  #XXX?

    cmp_ok _in_alert_cache($view1), '==', 10,
        'Correct number of alerts inserted';

    cmp_ok _in_alert_cache($view1, $user1), '==', 4,
       'Correct number of alerts for initial CURUSER filter addition (user1)';

    cmp_ok _in_alert_cache($view1, $user2), '==', 0,
       'Correct number of alerts for initial CURUSER filter addition (user2)';

    $view1->alert_set(24, $user2);  #XXX?

    cmp_ok _in_alert_cache($view1, $user1), '==', 4,
       'Still correct number of alerts for CURUSER filter addition (user1)';

    cmp_ok _in_alert_cache($view1, $user2), '==', 2,
       'Correct number of alerts for new CURUSER filter addition (user2)';

    cmp_ok _in_alert_cache($view1, undef), '==', 0,
       'No null user_id values inserted for CURUSER filter addition';

    # Change global view slightly, check alerts
    my $filter1;
    if($curuser_type eq 'person')
    {   $filter1 = { rules => [
            {
                column   => 'person1',
                type     => 'string',
                operator => 'equal',
                value    => '[CURUSER]',
            }, {
                column   => 'string1',
                type     => 'string',
                value    => 'Foo',
                operator => 'equal',
            }
        ] };
    }
    else
    {   $filter1 = { rules => [
            {
                column   => 'string1',
                type     => 'string',
                operator => 'equal',
                value    => '[CURUSER]',
            }, {
                column   => 'integer1',
                type     => 'string',
                value    => 100,
                operator => 'equal',
            }
        ] };
    }
    $views->view_update($view1 +> { filter => $filter1 });

    cmp_ok _in_alert_cache($view1, $user1), '==', 2,
       'Correct number of CURUSER alerts after filter change (user1)';

    cmp_ok _in_alert_cache($view1, $user1), '==', 2,
        'Correct number of CURUSER alerts after filter change (user2)';

    cmp_ok _in_alert_cache($view1, undef), '==', 0,
        'No null user_id values after filter change';

    # Update a record so as to cause a search_views with CURUSER
    my $row = $sheet->content->find_current_id(1);
    if ($curuser_type eq 'person')
    {   $row->cell_update(string1 => 'FooBar');
    }
    else {
    {   $row->cell_update(integer1 => 150);
    }

    # And remove curuser filter
    my $filter2;
    if($curuser_type eq 'person')
    {   $filter2 = { rule => {
            column   => 'string1',
            type     => 'string',
            value    => 'Foo',
            operator => 'equal',
        } };
    }
    else
    {   $filter2 = { rules =>[ {
            column   => 'integer1',
            type     => 'string',
            operator => 'equal',
            value    => '100',
        } };
    }
    $views->view_upate($view1 => { filter => $filter2 });

    cmp_ok $::db->search(AlertCache => { user_id => { '!=' => undef } })->count, '==', 0,
        'Correct number of user_id alerts after removal of curuser filter';

    cmp_ok _in_alert_cache($view1, undef), '==', 4,
        'Correct number of normal alerts after removal of curuser filter';
}

# Check alerts after update of calc column code
$sheet = make_sheet 1;

# First create a view with no filter

my $view = $sheet->view_create({
    name        => 'view1',
    is_global   => 1,
    columns     => [ 'calc1' ],
);

my $alert = $view->alert_set(24, $sheet->user);

cmp_ok _in_alert_cache($view), '==', 2,
    'Correct number of alerts inserted for initial calc test write';

cmp_ok _in_alert_send($view), '==', 0,
    'Start calc column change test with no alerts to send';

# Update calc column to same result (extra space to ensure update),
# should be no more alerts,

$layout->column_update(calc1 => {
    code => "function evaluate (L1daterange1) \n if L1daterange1 == null then return end \n return L1daterange1.from.year\nend ",
});

cmp_ok _in_alert_send($view), '==', 0,
    'Correct number of alerts after calc update with no change';

# Update calc column for different result (one record will change, other
# has same end year)
$layout->column_update(calc1 => {
    code => "function evaluate (L1daterange1) \n if L1daterange1 == null then return end \n return L1daterange1.to.year\nend"
});

cmp_ok _in_alert_send($view), '==', 1,
    'Correct number of alerts to send after calc update with change';

# Add filter, check alert after calc update
$::db->delete('AlertSend');

my $filter = { rules => {
    column   => 'calc1',
    type     => 'string',
    operator => 'greater',
    value    => '2011',
} };
$views->view_update($view, { filter => $filter });

cmp_ok _in_alert_cache($view), '==', 1,
    'Correct number of alert caches after filter applied';

$layout->column_update(calc1 => {
   code => "function evaluate (L1daterange1) \n if L1daterange1 == null then return end \n return L1daterange1.from.year\nend"
});

cmp_ok _in_alert_send($view), '==', 1,
    'Correct number of alerts to send after calc updated with filter in place';

# Mock tests for testing alerts for changes as a result of current date.
# Mocking the time in Perl will not affect Lua, so instead we insert the
# year hard-coded in the Lua code. Years of 2010 and 2014 are used for the tests.
foreach my $viewtype (qw/normal group global/)
{
    $sheet = make_sheet 1,
        calc_code => "function evaluate (L1daterange1) \nif L1daterange1.from.year < 2010 then return 1 else return 0 end\nend";

    # First create a view with no filter
    my $view = $sheet->view_create({
        name        => 'view1',
        is_global   => $viewtype eq 'group' || $viewtype eq 'global',
        group       => $viewtype eq 'group' && $sheet->group,
        columns     => [ 'calc1' ],
        filter      => { rule => {
            column   => 'calc1',
            type     => 'string',
            operator => 'equal',
            value    => '1',
        } },
    });

    $alert = $view->alert_set(24, $sheet->user);

    # Should be nothing in view initially - current year equal to 2014
    cmp_ok _in_alert_cache($view), '==', 1,
        'Correct number of alerts inserted for initial calc test write';

    cmp_ok _in_alert_send($view), '==', 0,
        'Start calc column change test with no alerts to send';

    # Wind date forward 4 years, should now appear in view
    $schema->resultset('Calc')->update({
        code => "function evaluate (L1daterange1) \nif L1daterange1.from.year < 2014 then return 1 else return 0 end\nend",
    });

    # Create new layout without user ID, as it would be in overnight updates
#XXX
    $layout = Linkspace::Layout->new(
        user                     => undef,
        config                   => $sheet->config,
        instance_id              => $sheet->layout->instance_id,
        user_permission_override => 1, # $self->user_permission_override,
    );

    $layout->column('calc1')->update_cached;

    cmp_ok _in_alert_cache($view), '==', 2,
        'Correct number of alerts inserted for initial calc test write';

    cmp_ok _in_alert_send($view), '==', 1,
        'Correct number of alerts after calc update with no change';
}

# Test some bulk alerts, which normally happen on code field updates
note "About to test alerts for bulk updates. This could take some time...";

# Some bulk data, almost all matching the filter, but not quite,
# to test big queries (otherwise current_ids is not searched)

$sheet = make_sheet 1,
    rows => [{ string1 => 'Bar' }, +{ string1 => 'Foo' } x 1000 ) ];

# Check alert count now, same query we perform at end
my $alerts_rs = $::db->search(AlertSend => {
    alert_id  => 1,
    layout_id => $columns->{string1}->id,
});
my $alert_count = $alerts_rs->count;

my $rules = { rule => {
        column   => 'string1',
        type     => 'string',
        value    => 'Foo',
        operator => 'equal',
}};

my $view1 = $views->view_create({
    name        => 'view1',
    filter      => $rules,
    columns     => [ 'string1' ],
});
my $alert1 = $view->alert_set(24, $sheet->user);

my @ids = $::db->resultset('Current')->get_column('id')->all;
pop @ids; # Again, not all current_ids, otherwise current_ids will not be searched

my $alert_send = $alert1->send_create({
    user        => $sheet->user,
    base_url    => undef, # $self->base_url,
    current_ids => \@ids,
    columns     => [ 'string1' ],  # needed?
});
$alert_send->process;

# We should now have 999 new alerts to send (1001 records, minus one popped from
# current_ids, minus first one not in view)
cmp_ok $alerts_rs->count, '==', $alert_count + 999,
    'Correct number of bulk alerts inserted';

done_testing;
