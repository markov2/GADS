
use Test::MockTime qw(set_fixed_time restore_time); # Load before DateTime
use Linkspace::Test;

# Fix all tests for this date so that CURDATE is consistent
set_fixed_time('10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

my $long = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum';

my $data = [
    {
        string1    => '',
        integer1   => -4,
        date1      => '',
        daterange1 => ['', ''],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },{
        string1    => '',
        integer1   => 5,
        date1      => '',
        daterange1 => ['', ''],
        enum1      => 'foo1',
        tree1      => 'tree3',
        curval1    => 2,
    },{
        string1    => '',
        integer1   => 6,
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree2',
        curval1    => 2,
    },{
        string1    => 'Foo',
        integer1   => 7,
        date1      => '2014-10-10',
        daterange1 => ['2013-10-10', '2013-12-03'],
        enum1      => 'foo1', # Changed to foo2 after creation to have multiple versions
        tree1      => 'tree1',
    },{
        string1    => 'FooBar',
        date1      => '2015-10-10',
        daterange1 => ['2009-01-04', '2017-06-03'],
        enum1      => 'foo2',
        tree1      => 'tree2',
        curval2    => 1,
    },{
        string1    => "${long}1",
        integer1   => 2,
    },{
        string1    => "${long}2",
        integer1   => 3,
    },
];

my $curval_sheet = make_sheet 2;
$curval_sheet->create_records;

my $sheet   = test_sheet
    data             => $data,
    curval           => 2,
    multivalue       => 1,
    group            => $curval_sheet->group,
    column_count     => { enum  => 1, curval => 2 },
    calc_return_type => 'date',
    calc_code        => <<'__CALC';
        function evaluate (L1daterange1)
            if type(L1daterange1) == "table" and L1daterange1[1] then
                dr1 = L1daterange1[1]
            elseif type(L1daterange1) == "table" and next(L1daterange1) == nil then
                dr1 = nil
            else
                dr1 = L1daterange1
            end
            if dr1 == nil then return end
            return dr1.from.epoch
        end
__CALC

my $layout  = $sheet->layout;

# Position curval first, as its internal _value fields are more
# likely to cause problems and therefore representative test failures
my @position = map $layout->column($_)->id, 
    qw/curval1 string1 integer1 date1 daterange1 enum1 tree1/;

$layout->position(@position);

$layout->create_column(calc => {
    user            => undef,
    name            => 'calc_int',
    return_type     => 'integer',
    code            => 'function evaluate (L1integer1) return L1integer1 end',
    set_permissions => +{ $sheet->group->id => $sheet->default_permissions },
});

$curval_layout->column_create(autocur => {
    name            => "$_-xx",
    refers_to_sheet => $sheet,
    related_column  => $layout->column($_),
}) for 'curval1', 'curval2';

my $curval_columns = $curval_layout->columns;
my $user = $sheet->user_normal1;

$sheet->current->row_by_current_id(6)->column('enum1')->set_value(8);

$data->[3]->{enum1} = 'foo2';  #XXX ???

# Add another curval field to a new table
my $curval_sheet2 = make_sheet 3,
    curval_offset    => 12,
    curval_field_ids => [ $sheet->column('integer1')->id ],
);
$curval_sheet2->create_records;

my $curval3 = $curval_layout->column_create(curval => {
    name             => 'curval3',
    refers_to_sheet  => $curval_sheet2,
    curval_field_ids => [ $curval_sheet2->column('string1')->id ],
    permissions      => { $sheet->group->id => $sheet->default_permissions },
);

my $r = $curval_sheet->content->current->record_for_row(0);
my ($curval3_value) = $curval_sheet2->content->current->column_ids;
$r->set_value($curval3, $curval3_value);


# Manually force one string to be empty and one to be undef.
# Both should be returned during a search on is_empty
$schema->resultset('String')->find(3)->update({ value => undef });
$schema->resultset('String')->find(4)->update({ value => '' });

my @filters = (
    {
        name  => 'string is Foo',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'equal',
        }],
        count => 1,
        aggregate => 7,
    },
    {
        name  => 'check case-insensitive search',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'foo',
            operator => 'begins_with',
        }],
        count => 2,
        aggregate => 7,
    },
    {
        name  => 'string is long1',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => "${long}1",
            operator => 'equal',
        }],
        count => 1,
        aggregate => 2,
    },
    {
        name  => 'string is long',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => $long,
            operator => 'begins_with',
        }],
        count => 2,
        aggregate => 5,
    },
    {
        name  => 'date is equal',
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => '2014-10-10',
            operator => 'equal',
        }],
        count => 2,
        aggregate => 13,
    },
    {
        name  => 'date using CURDATE',
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => 'CURDATE',
            operator => 'equal',
        }],
        count => 2,
        aggregate => 13,
    },
    {
        name  => 'date using CURDATE plus 1 year',
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => 'CURDATE + '.(86400 * 365), # Might be leap seconds etc, but close enough
            operator => 'equal',
        }],
        count => 1,
        aggregate => '',
    },
    {
        name  => 'date in calc',
        rules => [{
            id       => $layout->column('calc1')->id,
            type     => 'date',
            value    => 'CURDATE - '.(86400 * 365), # Might be leap seconds etc, but close enough
            operator => 'equal',
        }],
        count => 1,
        aggregate => 7,
    },
    {
        name  => 'negative filter for calc',
        rules => [{
            id       => $calc_int->id,
            type     => 'string',
            value    => -1,
            operator => 'less',
        }],
        count => 1,
        aggregate => -4,
    },
    {
        name  => 'date is empty',
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            operator => 'is_empty',
        }],
        count => 4,
        aggregate => 6,
    },
    {
        name  => 'date is empty - value as array ref',
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            operator => 'is_empty',
            value    => [],
        }],
        count => 4,
        aggregate => 6,
    },
    {
        name  => 'date is blank string', # Treat as empty
        rules => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => '',
            operator => 'equal',
        }],
        count     => 4,
        no_errors => 1, # Would normally bork
        aggregate => 6,
    },
    {
        name  => 'string begins with Foo',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'begins_with',
        }],
        count => 2,
        aggregate => 7,
    },
    {
        name  => 'string contains ooba',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'ooba',
            operator => 'contains',
        }],
        count => 1,
        aggregate => '',
    },
    {
        name  => 'string does not contain ooba',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'ooba',
            operator => 'not_contains',
        }],
        count => 6,
        aggregate => 19,
    },
    {
        name  => 'string does not begin with Foo',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'not_begins_with',
        }],
        count => 5,
        aggregate => 12,
    },
    {
        name  => 'string is empty',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            operator => 'is_empty',
        }],
        count => 3,
        aggregate => 7,
    },
    {
        name  => 'string is not equal to Foo',
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'not_equal',
        }],
        count => 6,
        aggregate => 12,
    },
    {
        name  => 'string is not equal to nothing', # should convert to not empty
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => '',
            operator => 'not_equal',
        }],
        count => 4,
        aggregate => 12,
    },
    {
        name  => 'string is not equal to nothing (array ref)', # should convert to not empty
        rules => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => [],
            operator => 'not_equal',
        }],
        count => 4,
        aggregate => 12,
    },
    {
        name  => 'greater than undefined value', # matches against empty instead
        rules => [{
            id       => $layout->column('integer1')->id,
            type     => 'integer',
            operator => 'greater',
        }],
        count => 1,
        aggregate => '',
    },
    {
        name  => 'negative integer filter',
        rules => [{
            id       => $layout->column('integer1')->id,
            type     => 'integer',
            operator => 'less',
            value    => -1,
        }],
        count => 1,
        aggregate => -4,
    },
    {
        name  => 'daterange less than',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2013-12-31',
            operator => 'less',
        }],
        count => 1,
        aggregate => 7,
    },
    {
        name  => 'daterange less or equal',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2013-12-31',
            operator => 'less_or_equal',
        }],
        count => 2,
        aggregate => 7,
    },
    {
        name  => 'daterange greater than',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2013-12-31',
            operator => 'greater',
        }],
        count => 1,
        aggregate => 6,
    },
    {
        name  => 'daterange greater or equal',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2014-10-10',
            operator => 'greater_or_equal',
        }],
        count => 2,
        aggregate => 6,
    },
    {
        name  => 'daterange equal',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2014-03-21 to 2015-03-01',
            operator => 'equal',
        }],
        count => 1,
        aggregate => 6,
    },
    {
        name  => 'daterange not equal',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2014-03-21 to 2015-03-01',
            operator => 'not_equal',
        }],
        count => 6,
        aggregate => 13,
    },
    {
        name  => 'daterange empty',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            operator => 'is_empty',
        }],
        count => 4,
        aggregate => 6,
    },
    {
        name  => 'daterange not empty',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            operator => 'is_not_empty',
        }],
        count => 3,
        aggregate => 13,
    },
    {
        name  => 'daterange contains',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2014-10-10',
            operator => 'contains',
        }],
        count => 2,
        aggregate => 6,
    },
    {
        name  => 'daterange does not contain',
        rules => [{
            id       => $layout->column('daterange1')->id,
            type     => 'daterange',
            value    => '2014-10-10',
            operator => 'not_contains',
        }],
        count => 5,
        aggregate => 13,
    },
    {
        name  => 'nested search',
        rules => [ {
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'begins_with',
        }, {
            rules => [ {
                id       => $layout->column('date1')->id,
                type     => 'date',
                    value    => '2015-10-10',
                    operator => 'equal',
            }, {
                id       => $layout->column('date1')->id,
                type     => 'date',
                value    => '2014-12-01',
                operator => 'greater',
            } ],
        } ],
        condition => 'AND',
        count     => 1,
        aggregate => '',
    },
    {
        name  => 'Search using enum with different tree in view',
        rules => [{
            id       => $layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        }],
        count => 3,
        aggregate => 7,
    },
    {
        name  => 'Search negative multivalue enum',
        rules => [{
            id       => $layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'not_equal',
        }],
        count => 4,
        aggregate => 12,
    },
    {
        name  => 'Search using enum with curval in view',
        columns => [$layout->column('curval1')->id],
        rules => [{
            id       => $layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        }],
        count => 3,
        values => {
            $layout->column('curval1')->id => "Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012",
        },
        aggregate => 7,
    },
    {
        name    => 'Search 2 using enum with different tree in view',
        columns => [ $layout->column('tree1')->id, $layout->column('enum1')->id ],
        rules   => [ {
            id       => $layout->column('tree1')->id,
            type     => 'string',
            value    => 'tree1',
            operator => 'equal',
        } ],
        count => 2,
        aggregate => 3,
    },
    {
        name  => 'Search for ID',
        columns => [ $layout->column('string1')->id ],
        rules => [ {
            id       => $layout->column('_id')->id,
            type     => 'integer',
            value    => '4',
            operator => 'equal',
        } ],
        count => 1,
        aggregate => 5,
    },
    {
        name  => 'Search for multiple IDs',
        columns => [$layout->column('string1')->id],
        rules => [ {
            id       => $layout->column('_id')->id,
            type     => 'integer',
            value    => ['4', '5'],
            operator => 'equal',
        } ],
        count => 2,
        aggregate => 11,
    },
    {
        name  => 'Search for empty IDs',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('_id')->id,
                type     => 'integer',
                value    => [],
                operator => 'equal',
            }
        ],
        count => 0,
        aggregate => '',
    },
    {
        name  => 'Search for version date 1',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('_version_datetime')->id,
                type     => 'date',
                value    => '2014-10-10',
                operator => 'greater',
            },
            {
                id       => $layout->column('_version_datetime')->id,
                type     => 'date',
                value    => '2014-10-11',
                operator => 'less',
            }
        ],
        condition => 'AND',
        count     => 7,
        aggregate => 19,
    },
    {
        name  => 'Search for version date 2',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('_version_datetime')->id,
                type     => 'date',
                value    => '2014-10-15',
                operator => 'greater',
            },
        ],
        count => 0,
        aggregate => '',
    },
    {
        name  => 'Search for created date',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('_created')->id,
                type     => 'date',
                value    => '2014-10-15',
                operator => 'less',
            },
        ],
        count => 7,
        aggregate => 19,
    },
    {
        name  => 'Search for version editor',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('_version_user')->id,
                type     => 'string',
                value    => $user->value,
                operator => 'equal',
            },
        ],
        count     => 1, # Other records written by superadmin user on start
        aggregate => 7,
    },
    {
        name  => 'Search for invalid date',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('date1')->id,
                type     => 'date',
                value    => '20188-01',
                operator => 'equal',
            },
        ],
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
    {
        name  => 'Search for invalid daterange',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('daterange1')->id,
                type     => 'date',
                value    => '20188-01 XX',
                operator => 'equal',
            },
        ],
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
    {
        name  => 'Search for blank calc date as empty string (array ref)',
        rules => [{
            id       => $layout->column('calc1')->id,
            type     => 'date',
            value    => [''],
            operator => 'equal',
        }],
        count     => 4,
        aggregate => 6,
    },
    {
        name  => 'Search by curval ID',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('curval1')->id,
                type     => 'string',
                value    => '2',
                operator => 'equal',
            },
        ],
        count     => 2,
        aggregate => 11,
    },
    {
        name  => 'Search by curval ID not equal',
        columns => [$layout->column('string1')->id],
        rules => [
            {
                id       => $layout->column('curval1')->id,
                type     => 'string',
                value    => '2',
                operator => 'not_equal',
            },
        ],
        count     => 5,
        aggregate => 8,
    },
    {
        name  => 'Search curval ID and enum, only curval in view',
        columns => [ $layout->column('curval1')->id ], # Ensure it's added as first join
        rules => [{
            id       => $layout->column('curval1')->id,
            type     => 'string',
            value    => '1',
            operator => 'equal',
        }, {
            id       => $layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        }],
        condition => 'AND',
        count     => 1,
        aggregate => -4,
    },
    {
        name    => 'Search by curval field',
        columns => [ $layout->column('string1')->id ],
        rules   => [{
            id       => $layout->column('curval1')->id .'_'. $curval_layout->column('string1')->id,
            type     => 'string',
            value    => 'Bar',
            operator => 'equal',
        }],
        count     => 2,
        aggregate => 11,
    },
    {
        name    => 'Search by curval field not equal',
        columns => [ $layout->column('string1')->id ],
        rules   => [ {
            id       => $layout->column('curval1')->id .'_'. $curval_layout->column('string1')->id,
            type     => 'string',
            value    => 'Bar',
            operator => 'not_equal',
        } ],
        count     => 5,
        aggregate => 8,
    },
    {
        name  => 'Search by curval enum field',
        columns => [ $layout->column('enum1')->id ],
        rules => [ {
            id       => $layout->column('curval1')->id .'_'. $curval_layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo2',
            operator => 'equal',
        } ],
        count     => 2,
        aggregate => 11,
    },
    {
        name    => 'Search by curval within curval',
        columns => [ $layout->column('curval1')->id ],
        rules   => [ {
            id       => $layout->column('curval1')->id .'_'. $curval3->id,
            type     => 'string',
            value    => $curval3_value,
            operator => 'equal',
        } ],
        count     => 1,
        aggregate => -4,
    },
    {
        name    => 'Search by curval enum field across 2 curvals',
        columns => [ $layout->column('enum1')->id ],
        rules   => [ {
            id       => $layout->column('curval1')->id .'_'. $curval_layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo2',
            operator => 'equal',
        }, {
            id       => $layout->column('curval2')->id .'_'. $curval_layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        } ],
        condition => 'OR',
        count     => 3,
        aggregate => 11,
    },
    {
        name    => 'Search by autocur ID',
        columns => [$curval_layout->column('autocur1')->id],
        rules   => [ {
            id       => $curval_layout->column('autocur1')->id,
            type     => 'string',
            value    => '3',
            operator => 'equal',
        } ],
        count     => 1,
        layout    => $curval_layout,
        aggregate => 50,
    },
    {
        name    => 'Search by autocur ID not equal',
        columns => [ $curval_layout->column('autocur1')->id ],
        rules   => [ {
            id       => $curval_layout->column('autocur1')->id,
            type     => 'string',
            value    => '3',
            operator => 'not_equal',
        } ],
        count       => 1,
        # Autocur treated as a multivalue with a single row with 2 different
        # values that are counted separately on a graph
        count_graph => 2,
        layout      => $curval_layout,
        aggregate   => 99,
    },
    {
        name  => 'Search by autocur enum field',
        columns => [$curval_layout->column('string1')->id],
        rules => [ {
            id       => $curval_layout->column('autocur1')->id .'_'. $layout->column('enum1')->id,
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        } ],
        count     => 2,
        layout    => $curval_layout,
        aggregate => 149,
    },
    {
        name  => 'Search for invalid autocur',
        columns => [ $curval_layout->column('autocur1')->id ],
        rules => [ {
            id       => $curval_layout->column('autocur1')->id,
            type     => 'string',
            value    => 'Foobar',
            operator => 'equal',
        } ],
        count     => 0,
        no_errors => 1,
        layout    => $curval_layout,
        aggregate => '',
    },
    {
        name  => 'Search by record ID',
        columns => [ $layout->column('string1')->id ],
        rules => [ {
            id       => $layout->column('ID')->id,
            type     => 'string',
            value    => '3',
            operator => 'equal',
        } ],
        count     => 1,
        aggregate => -4,
    },
    {
        name  => 'Search by invalid record ID',
        columns => [ $layout->column('string1')->id ],
        rules => [ {
            id       => $layout->column('ID')->id,
            type     => 'string',
            value    => '3DD',
            operator => 'equal',
        } ],
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
);

foreach my $multivalue (0..1)
{
    $sheet->set_multivalue($multivalue);

    # Set aggregate fields. Only needs to be done once, and after that the user
    # does not have permission to write the field settings
    my $integer1        = $layout->column('integer1');
    my $integer1_curval = $curval_layout->column('integer1');

    if(!$multivalue)
    {   $integer1->column_update(aggregate => 'sum');
        $integer1_curval->column_update(aggregate => 'sum');
    }

    # Run 2 loops, one without the standard layout from the initial build, and a
    # second with the layouts all built from scratch using GADS::Instances
    foreach my $layout_from_instances (0..1)
    {
        my $instances;
        if ($layout_from_instances)
        {
            $layout = $instances->layout($layout->instance_id);
        }

        foreach my $filter (@filters)
        {   my $layout_filter = $filter->{layout};
            my $sheet = ($layout_filter || $layout)->sheet;

            my $rules = {
                rules     => $filter->{rules},
                condition => $filter->{condition},
            };

            my $view = try { $sheet->views->view_create({
                name        => 'Test view',
                filter      => $rules,
                columns     => $filter->{columns} || [ qw/string1 tree1/ ],
                layout      => $layout_filter || $layout,
            }) };

            # If the filter is expected to bork, then check that it actually does first
            if($filter->{no_errors})
            {   ok $@, "Failed to write view with invalid value, test: $filter->{name}";
                is $@->wasFatal->reason, 'ERROR',
                     "Generated user error when writing view with invalid value";
            }

#XXX impossible
            $view->write(no_errors => $filter->{no_errors});

            my $page = $sheet->content->search(view => $view);

            cmp_ok $records->count, '==', $filter->{count},
                 "$filter->{name} for record count()";

            cmp_ok scalar @{$records->results}, '==', $filter->{count},
                 "$filter->{name} actual number records";

            if(my $test_values = $filter->{values})
            {   foreach my $field (keys %$test_values)
                {   is $page->row(0)->cell($field)->as_string, $test_values->{$field},
                       "Test value of $filter->{name} correct";
                }
            }

            $sheet->views->view_update($view, { sortings => [ [$view_columns, ['asc']] ]});
            my $page = $sheet->content->search(view => $view);

            cmp_ok $records->count, '==', $filter->{count},
                "$filter->{name} for record count()";

            cmp_ok scalar @{$records->results}, '==', $filter->{count},
                "$filter->{name} actual number records";

            # Basic aggregate tests
            {   my @column_ids = @{$view->columns};
                my $int_id = $records->sheet_id == $curval_sheet->id
                    ? $integer1_curval->id : $integer1->id;

                push @column_ids, $int_id if ! grep $_ == $int_id, @column_ids;
                $sheet->views->view_update({columns => \@column_ids});

                my $aggregate = $page->aggregate_results;
                is $aggregate->cell($int_id)->as_string, $filter->{aggregate},
                    "Aggregate integer value correct";
            }

            # Basic graph test. Total of points on graph should match the number of results
            my $axis = $filter->{columns}->[0] || $layout->column('string1')->id;
            my $graph = $sheet->graphs->graph_create({
                title => 'Test',
                type => 'bar',
                current_user => $sheet->user,
                x_axis => $axis,
                y_axis => $axis,
                y_axis_stack => 'count',
            );

            my $records_group = GADS::RecordsGraph->new(
                user              => $user,
                layout            => $layout_filter || $layout,
            );
            my $graph_data = GADS::Graph::Data->new(
                id      => $graph->id,
                view    => $view,
                records => $records_group,
            );

            # Count total number of records
            my $graph_total = sum map scalar($_), @{$graph_data->points->[0]};
            my $count = $filter->{count_graph} || $filter->{count};

            cmp_ok $graph_total, '==', $count,
                "Item total on graph matches table for $filter->{name}";
        }
    }
}

foreach my $multivalue (0..1)
{
    $sheet->set_multivalue($multivalue);

    $layout = $sheet->layout;
    $columns = $sheet->columns;

    my $rules1 = {
        rules     => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => '2014-10-10',
            operator => 'equal',
        }],
    };

    my $view_limit = $sheet->views->view_create({
        name        => 'Limit to view',
        filter      => $rules1,
        is_for_admins => 1,
    });

    $user->set_view_limits([$view_limit]);

    my $rules2 = {
        rules     => [{
            id       => $layout->column('string1')->id,
            type     => 'string',
            value    => 'Foo',
            operator => 'begins_with',
        }],
    };

    my $view = $sheet->views->view_create({
        name        => 'Foo',
        filter      => $rules2,
    });

    my $data = $sheet->content;
    my $page = $data->search(view => $view);

    cmp_ok $page->count, '==', 1, 'Correct number of results when limiting to a view';

    # Check can only directly access correct records. Test with and without any
    # columns selected.
    for (0..1)
    {
        my $cols_select = $_ ? [] : undef;
        is $page->find_current_id(5, columns => $cols_select)->current_id, 5,
            "Retrieved viewable current ID 5 in limited view";

        is $page->find_record_id(5, columns => $cols_select)->current_id, 5,
            "Retrieved viewable record ID 5 in limited view";

        try { $page->find_current_id(4) };
        ok( $@, "Failed to retrieve non-viewable current ID 4 in limited view" );

        try { $page->find_record_id(4) };
        ok( $@, "Failed to retrieve non-viewable record ID 4 in limited view" );

        # Temporarily flag record as deleted and check it can't be shown
        $schema->resultset('Current')->find(5)->update({ deleted => DateTime->now });

        try { $page->find_current_id(5) };
        like $@, qr/Requested record not found/, "Failed to find deleted current ID 5";

        try { $page->find_record_id(5) };
        like $@, qr/Requested record not found/, "Failed to find deleted record ID 5";

        # Draft record whilst view limit in force
        my $draft = $data->draft_create({ cells => [ string1 => 'Draft' ] });
        $draft->load_remembered_values;
        is $draft->field('string1')->as_string, "Draft", "Draft sub-record retrieved";

        # Reset
        $schema->resultset('Current')->find(5)->update({ deleted => undef });
    }

    # Add a second view limit
    my $rules2 = {
        rules     => [{
            id       => $layout->column('date1')->id,
            type     => 'date',
            value    => '2015-10-10',
            operator => 'equal',
        }],
    };

    my $view_limit2 = $sheet->views->create_view({
        name        => 'Limit to view2',
        filter      => $rules2,
    );

    $user->set_view_limits([$view_limit, $view_limit2]);

    my $page = $sheet->search(view => $view);
    cmp_ok $records->count, '==', 2, 'Correct number of results when limiting to 2 views';

    # view limit with a view with negative match multivalue filter
    # (this has caused recusion in the past)
    {
        # First define limit view
        my $rules3 = {
            rules     => [{
                id       => $layout->column('enum1')->id,
                type     => 'string',
                value    => 'foo1',
                operator => 'not_equal',
            }],
        };

        my $view_limit3 = $sheet->views->create_view({
            name        => 'limit to view',
            filter      => $rules3,
        });

        $user->set_view_limits([ $view_limit3 ]);

        # Then add a normal view
        my $rules4 = {
            rules     => [{
                id       => $layout->column('date1')->id,
                type     => 'string',
                value    => '2014-10-10',
                operator => 'equal',
            }],
        };

        my $view = $sheet->views->create_view({
            name        => 'date1',
            filter      => $rules4,
        );

        my $page = $sheet->search(view => $view);

        cmp_ok $page->number_rows, '==', 1,
            'Correct result count when limiting to negative multivalue view';

        cmp_ok scalar @{$page->rows}, '==', 1,
            'Correct number of results when limiting to negative multivalue view';
    }

    # Quick searches
    # Limited view still defined
    $records->search('Foobar');
    is (@{$records->results}, 0, 'Correct number of quick search results when limiting to a view');
    # And again with numerical search (also searches record IDs). Current ID in limited view
    $records->clear;
    $records->search(8);
    is (@{$records->results}, 1, 'Correct number of quick search results for number when limiting to a view (match)');
    # This time a current ID that is not in limited view
    $records->clear;
    $records->search(5);
    is (@{$records->results}, 0, 'Correct number of quick search results for number when limiting to a view (no match)');
    # Reset and do again with non-negative view
    $records->clear;
    $user->set_view_limits([$view_limit]);
    $records->search('Foobar');
    is (@{$records->results}, 0, 'Correct number of quick search results when limiting to a view');
    # Current ID in limited view
    $records->clear;
    $records->search(8);
    is (@{$records->results}, 0, 'Correct number of quick search results for number when limiting to a view (match)');
    # Current ID that is not in limited view
    $records->clear;
    $records->search(5);
    is (@{$records->results}, 1, 'Correct number of quick search results for number when limiting to a view (no match)');

    # Same again but limited by enumval
    $view_limit->filter(GADS::Filter->new(
        as_hash => {
            rules     => [{
                id       => $layout->column('enum1')->id,
                type     => 'string',
                value    => 'foo2',
                operator => 'equal',
            }],
        },
    ));
    $view_limit->write;

    $records = GADS::Records->new(
        user    => $user,
        layout  => $layout,
    );
    is ($records->count, 2, 'Correct number of results when limiting to a view with enumval');
    {
        my $limit = $schema->resultset('ViewLimit')->create({
            user_id => $user->id,
            view_id => $view_limit->id,
        });
        my $record = GADS::Record->new(
            user   => $user,
            layout => $layout,
        );
        is( $record->find_current_id(7)->current_id, 7, "Retrieved record within limited view" );
        $limit->delete;
    }
    $records->clear;
    $records->search('2014-10-10');
    is (@{$records->results}, 1, 'Correct number of quick search results when limiting to a view with enumval');
    # Check that record can be retrieved for edit
    my $record = GADS::Record->new(
        user                 => $user,
        layout               => $layout,
        curcommon_all_fields => 1, # Used for edits
    );
    $record->find_current_id($records->single->current_id);

    # Same again but limited by curval
    $view_limit->filter(GADS::Filter->new(
        as_hash => {
            rules     => [{
                id       => $layout->column('curval1')->id,
                type     => 'string',
                value    => '1',
                operator => 'equal',
            }],
        },
    ));
    $view_limit->write;
    $records = GADS::Records->new(
        view_limits => [ $view_limit ],
        user    => $user,
        layout  => $layout,
    );
    is ($records->count, 1, 'Correct number of results when limiting to a view with curval');
    is (@{$records->results}, 1, 'Correct number of results when limiting to a view with curval');

    # Check that record can be retrieved for edit
    $record = GADS::Record->new(
        user                 => $user,
        layout               => $layout,
        curcommon_all_fields => 1, # Used for edits
    );
    $record->find_current_id($records->single->current_id);

    {
        my $limit = $schema->resultset('ViewLimit')->create({
            user_id => $user->id,
            view_id => $view_limit->id,
        });
        my $record = GADS::Record->new(
            user   => $user,
            layout => $layout,
        );
        is( $record->find_current_id(3)->current_id, 3, "Retrieved record within limited view" );
        $limit->delete;
    }
    $records->clear;
    $records->search('foo1');
    is (@{$records->results}, 1, 'Correct number of quick search results when limiting to a view with curval');

    # Now normal
    $user->set_view_limits([]);
    $records = GADS::Records->new(
        user    => $user,
        layout  => $layout,
    );
    $records->clear;
    $records->search('2014-10-10');
    is (@{$records->results}, 4, 'Quick search for 2014-10-10');
    $records->clear;
    $records->search('Foo');
    is (@{$records->results}, 3, 'Quick search for foo');
    $records->clear;
    $records->search('Foo*');
    is (@{$records->results}, 5, 'Quick search for foo*');
    $records->clear;
    $records->search('99');
    is (@{$records->results}, 2, 'Quick search for 99');
    $records->clear;
    $records->search('1979-01-204');
    is (@{$records->results}, 0, 'Quick search for invalid date');

    # Specific record retrieval
    $record = GADS::Record->new(
        user   => $user,
        layout => $layout,
    );
    is( $record->find_record_id(3)->record_id, 3, "Retrieved history record ID 3" );
    $record->clear;
    is( $record->find_current_id(3)->current_id, 3, "Retrieved current ID 3" );
    # Find records from different layout
    $record->clear;
    is( $record->find_record_id(1)->record_id, 1, "Retrieved history record ID 1 from other datasheet" );
    $record->clear;
    is( $record->find_current_id(1)->current_id, 1, "Retrieved current ID 1 from other datasheet" );
    # Records that don't exist
    $record->clear;
    try { $record->find_record_id(100) };
    like( $@, qr/Record version ID 100 not found/, "Correct error when finding record version that does not exist" );
    $record->clear;
    try { $record->find_current_id(100) };
    like( $@, qr/Record ID 100 not found/, "Correct error when finding record ID that does not exist" );
    try { $record->find_current_id('XYXY') };
    like( $@, qr/Invalid record ID/, "Correct error when finding record ID that is invalid" );
    try { $record->find_current_id('123XYXY') };
    like( $@, qr/Invalid record ID/, "Correct error when finding record ID that is invalid (2)" );
}

{
    # Test view_limit_extra functionality
    my $sheet = t::lib::DataSheet->new(data =>
    [
        {
            string1    => 'FooBar',
            integer1   => 50,
        },
        {
            string1    => 'Bar',
            integer1   => 100,
        },
        {
            string1    => 'Foo',
            integer1   => 150,
        },
        {
            string1    => 'FooBar',
            integer1   => 200,
        },
    ]);
    $sheet->create_records;
    my $layout  = $sheet->layout;
    my $columns = $sheet->columns;

    my $rules = GADS::Filter->new(
        as_hash => {
            rules     => [{
                id       => $layout->column('string1')->id,
                type     => 'string',
                value    => 'FooBar',
                operator => 'equal',
            }],
        },
    );

    my $limit_extra1 = GADS::View->new(
        name        => 'Limit to view extra',
        filter      => $rules,
        instance_id => $layout->instance_id,
        layout      => $layout,
        user        => $sheet->user,
    );
    $limit_extra1->write;

    $rules = GADS::Filter->new(
        as_hash => {
            rules     => [{
                id       => $layout->column('integer1')->id,
                type     => 'string',
                value    => '75',
                operator => 'greater',
            }],
        },
    );

    my $limit_extra2 = GADS::View->new(
        name        => 'Limit to view extra',
        filter      => $rules,
        instance_id => $layout->instance_id,
        layout      => $layout,
        user        => $sheet->user,
    );
    $limit_extra2->write;

    $schema->resultset('Instance')->find($layout->instance_id)->update({
        default_view_limit_extra_id => $limit_extra1->id,
    });
    $layout->clear;

    my $records = GADS::Records->new(
        user    => $sheet->user,
        layout  => $layout,
    );
    my $string1 = $layout->column('string1')->id;
    is($records->count, 2, 'Correct number of results when limiting to a view limit extra');
    is($records->single->fields->{$string1}->as_string, "FooBar", "Correct limited record");

    $records = GADS::Records->new(
        layout              => $layout,
        view_limit_extra_id => $limit_extra2->id,
    );
    is ($records->count, 3, 'Correct number of results when changing view limit extra');
    is($records->single->fields->{$string1}->as_string, "Bar", "Correct limited record when changed");

    my $user = $sheet->user;
    $user->set_view_limits([ $limit_extra1 ]);
    $records = GADS::Records->new(
        layout              => $layout,
        view_limit_extra_id => $limit_extra2->id,
    );
    is ($records->count, 1, 'Correct number of results with both view limits and extra limits');
    is($records->single->fields->{$string1}->as_string, "FooBar", "Correct limited record for both types of limit");
}

# Check sorting functionality

{   # First check default_sort functionality

    # ASC
    $sheet->sheet_update({sort_column => $layout->column('_id'), sort_type => 'asc'});
    my $page1 = $sheet->content->search;
    is $page1->row(0)->current_id, 3, "Correct first record for default_sort (asc)";
    is $page1->row(-1)->current_id, 9, "Correct last record for default_sort (asc)";

    # DESC
    $sheet->sheet_update({sort_column => $layout->column('_id'), sort_type => 'desc'});
    my $page2 = $sheet->content->search;
    is $page2->row(0)->current_id, 9, "Correct first record for default_sort (desc)";
    is $page2->row(-1)->current_id, 3, "Correct last record for default_sort (desc)";

    # Column from view
    $sheet->sheet_update({sort_column => $layout->column('integer1'), sort_type => 'asc'});
    my $page3 = $sheet->content->search;
    is $page3->row(0)->current_id, 6, "Correct first record for default_sort (column in view)";
    is $page3->row(-1)->current_id, 7, "Correct last record for default_sort (column in view)";

    # Standard sort parameter for search()
    my $page4 = $sheet->content->search(
        sort => { type => 'desc', id   => $layout->column('integer1')->id },
    );
    is $page4->row(0)->current_id, 6, "Correct first record for standard sort";
    is $page4->row(-1)->current_id, 7, "Correct last record for standard sort";

    # Standard sort parameter for search() with invalid column. This can happen if the
    # user switches tables and there is still a sort parameter in the session. In this
    # case, it should revert to the default search.
    $sheet->sheet_update({sort_column => $layout->column('integer1'), sort_type => 'desc' });
    my $page5 = $sheet->content->search(sort => { type => 'desc', id => -1000 });
    is $page5->row(0)->current_id, 6, "Correct first record for standard sort";
    is $page5->row(-1)->current_id, 7, "Correct last record for standard sort";
}

my @sorts = (
    {
        name         => 'Sort by ID descending',
        show_columns => [qw/string1 enum1/],
        sort_by      => [undef],
        sort_type    => ['desc'],
        first        => qr/^9$/,
        last         => qr/^3$/,
    },
    {
        name         => 'Sort by single column in view ascending',
        show_columns => [qw/string1 enum1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(6|7)$/,
    },
    {
        name         => 'Sort by single column not in view ascending',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(6|7)$/,
    },
    {
        name         => 'Sort by single column not in view descending',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['desc'],
        first        => qr/^(6|7)$/,
        last         => qr/^(8|9)$/,
    },
    {
        name         => 'Sort by single column not in view ascending (opposite enum columns)',
        show_columns => [qw/string1 enum1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(4)$/,
    },
    {
        name         => 'Sort by two columns, one in view one not in view, asc then desc',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1 daterange1/],
        sort_type    => ['asc', 'desc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(7)$/,
    },
    {
        name         => 'Sort with filter on enums',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(3)$/,
        first_string => { curval1 => '' },
        last         => qr/^(6)$/,
        last_string  => { curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012' },
        max_id       => 6,
        min_id       => 3,
        count        => 2,
        filter       => {
            rules => [
                {
                    name     => 'tree1',
                    type     => 'string',
                    value    => 'tree1',
                    operator => 'equal',
                },
            ],
        },
    },
    # Sometimes _value table numbers can get mixed up, so try the opposite way round as well
    {
        name         => 'Sort with filter on enums - opposite filter/sort combo',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(3)$/,
        last         => qr/^(4)$/,
        max_id       => 5,
        min_id       => 3,
        count        => 3,
        filter       => {
            rules => [
                {
                    name     => 'enum1',
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                },
            ],
        },
    },
    {
        name         => 'Sort by enum that is after another enum in the fetched column',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(4)$/,
    },
    {
        name         => 'Sort by enum with filter on curval',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(4|5)$/,
        last         => qr/^(7)$/,
        max_id       => 7,
        min_id       => 4,
        count        => 3,
        filter       => {
            rules => [
                {
                    name     => 'curval1_'.$curval_layout->column('enum1')->id,
                    type     => 'string',
                    value    => 'foo2',
                    operator => 'equal',
                },
                {
                    name     => 'curval2_'.$curval_layout->column('enum1')->id,
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                },
            ],
            condition => 'OR',
        },
    },
    {
        name         => 'Sort by curval with filter on curval',
        show_columns => [ qw/enum1 curval1 curval2/ ],
        sort_by      => [ qw/curval1/ ],
        sort_type    => ['asc'],
        first        => qr/^(4|5)$/,
        last         => qr/^(3)$/,
        max_id       => 5,
        min_id       => 3,
        count        => 3,
        filter       => {
            rules => [ {
                name     => 'curval1_'.$curval_layout->column('enum1')->id,
                type     => 'string',
                value    => 'foo1',
                operator => 'equal',
            }, {
                name     => 'curval1_'.$curval_layout->column('enum1')->id,
                type     => 'string',
                value    => 'foo2',
                operator => 'equal',
            } ],
            condition => 'OR',
        },
    },
    {
        name           => 'Sort by field in curval',
        show_columns   => [qw/enum1 curval1 curval2/],
        sort_by        => [qw/string1/],
        sort_by_parent => [qw/curval1/],
        sort_type      => ['asc'],
        first          => qr/^(6|7|8|9)$/,
        last           => qr/^(3)$/,
        max_id         => 9,
        min_id         => 3,
        count          => 7,
    },
    {
        name         => 'Sort by curval without curval in view',
        show_columns => [qw/string1/],
        sort_by      => [qw/curval1/],
        sort_type    => ['asc'],
        first        => qr/^(6|7|8|9)$/,
        last         => qr/^(3)$/,
        max_id       => 9,
        min_id       => 3,
        count        => 7,
    },
    {
        name           => 'Sort by field in curval without curval in view',
        show_columns   => [qw/integer1/],
        sort_by        => [qw/string1/],
        sort_by_parent => [qw/curval1/],
        sort_type      => ['asc'],
        first          => qr/^(6|7|8|9)$/,
        last           => qr/^(3)$/,
        max_id         => 9,
        min_id         => 3,
        count          => 7,
    },
);

foreach my $multivalue (0..1)
{
    $sheet->clear_not_data(multivalue => $multivalue);

    my $cid_adjust = 9; # For some reason database restarts at same ID second time

    foreach my $sort (@sorts)
    {   my @sort_types = @{$sort->{sort_type}};
        my $sort_by    = $sort->{sort_by};
        my $filter     = $sheet->convert_filter($sort->{filter}) || {};

        my @sort_by;
        if(my $parents = $sort->{sort_by_parent})
        {   my @children = @$sort_by;
            foreach my $parent (@$parents)
            {   my $cname = shift @children;
                my $id    = $curval->layout->column($cname)->id;
                my $parent_id = $layout->column($parent)->id;
                push @sort_by, "${parent_id}_$id";
            }
        }
        else
        {   @sort_by = map $layout->column($_ || '_id'), @$sort_by;
        }

        my $view = $sheet->views->view_create({
            name     => 'Test view',
            columns  => $sort->{show_columns},
            filter   => $filter,
            sortings => [ [ \@sort_by, $sort_type ] ],
        });

        foreach my $pass (1..$passes)
        {    my $sort_type  = @sort_types==1 && $pass==3
              ? [ $sort_types[0] eq 'asc' ? 'desc' : 'asc' ]
              : \@sort_types;

            $view->view_update({ sortings => [ [ \@sort_by, $sort_type ] ] });
            my $page = $sheet->content->search(
                view     => $view,
                sortings => $sorting,
            );

        ### Test override of sort first     XXX was "pass1"

        {   ok 1, "testing sort $sort->{name} is overriden";

            my $page = $sheet->content->search(
                view     => $view,
                sortings => +{ type => 'desc', id => $layout->column('_id'),
            );

            my $first = $sort->{max_id} || 9;
            my $last  = $sort->{min_id} || 3;

            # 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            is $page->row(0)->current_id - $cid_adjust,
               $first,
               '... first record for sort override';

            if(my $fs = $sort->{first_string})
            {   foreach my $colname (keys %$fs)
                {   is $page->row(0)->field($colname)->as_string,
                       $sort->{first_string}->{$colname},
                       "... first record value for $colname";
                }
            }

            my $new_pagenr = $sort->{count} || 7;
            $page->window(page_number => $new_pagenr);

            ok defined $new_page, "... moved to other page";
            is $new_page->page_number, $sort->{count} || 7,
               "... moved to page $newpagenr";

            is $new_page->row(-1)->current_id - $cid_adjust,
               $last,
               "... last record for sort override";

            if(my $ls = $sort->{last_string})
            {   foreach my $colname (keys %$ls)
                {   is $page->row(0)->field($colname)->as_string,
                       $sort->{last_string}->{$colname},
                       "last record value for $colname";
                }
            }

            # Basic graph test. Total of points on graph should match the number of results.
            # Even though graphs do not use sorting, so a test with a sort
            # as the user may still be using a view with a sort defined.
            my $axis = $layout->column('string1')->id;
            my $graph = $sheet->graphs->graph_create({
                title        => 'Test',
                type         => 'bar',
                current_user => $sheet->user,
                x_axis       => $axis,
                y_axis       => $axis,
                y_axis_stack => 'count',
                view         => $view,
            });

            # Count total number of records  XXX $graph->content_points?
            my $graph_total = sum map { scalar @$_ }, $graph->content->points->[0]};

            my $count = $sort->{filter} ? $sort->{count} : 7;
            is $graph_total, $count, "Item total on graph matches table for $sort->{name}";
            $sheet->graphs->graph_delete($graph);
        }

        ### Use the sort from the view    XXX was pass2

        {   ok 1, "testing sort $sort->{name}, sort defined by view";

            my $page = $sheet->content->search(view => $view);

            is $page->all_rows, $sort->{count},
                '... number of records in results'
                if $sort->{count};

            like $page->row(0)->current_id - $cid_adjust, $sort->{first},
                 '... first record';

            like $page->row(-1)->current_id - $cid_adjust, $sort->{last},
                '... last record';

            # Then switch to 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            like $page->row(0)->current_id - $cid_adjust, $sort->{first},
                '... correct first record';

            $page->window(page_number => $sort->{count} || 7);

            like $page->row(0)->current_id - $cid_adjust, $sort->{last},
                '... last record';
        }

        ### Reverse sorting     XXX was pass3

        if(@sort_types==1)
        {   ok 1, "testing sort $sort->{name}, sort reversed by view";

            my $rev = $sort_types[0] eq 'asc' ? 'desc' : 'asc';
            $view->view_update({ sortings => [ [ \@sort_by, $rev ] ] });

            my $page = $sheet->content->search(view => $view);

            is $page->all_rows, $sort->{count}, '... number of records in results'
                if $sort->{count};

            like $page->row(0)->current_id - $cid_adjust, $sort->{last},
                '... first record in reverse';

            like $page->row(-1)->current_id - $cid_adjust, $sort->{last},
                '... last record in reverse';

            # Then switch to 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            like( $page->row(0)->current_id - $cid_adjust, $sort->{last}, "Correct first record for sort $sort->{name} in reverse");

                $records->page($sort->{count} || 7);
            like $page->row(0)->current_id - $cid_adjust, $sort->{first}, "Correct last record for sort $sort->{name} in reverse");
        }

        #### Count only    XXX was pass4
        # If doing a count with the sort, then do an extra pass, one to check that actual
        # number of rows retrieved, and one to check the count calculation function
        if(my $count = $sort->{count})
        {   ok 1, "testing sort $sort->{name}, count only";

            my $page = $sheet->content->search(view => $view);
            is $page->count, $count, '... record count';

ok ! $page->_loaded_any_record;
        }

        $sheet->views->view_delete($view);
    }
}

restore_time();

done_testing;
