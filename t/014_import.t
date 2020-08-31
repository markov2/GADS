use Test::More; # tests => 1;
use strict;
use warnings;

use Test::MockTime qw(set_fixed_time restore_time); # Load before DateTime
use Log::Report;
use GADS::Import;

use t::lib::DataSheet;

$ENV{GADS_NO_FORK} = 1; # Prevent forking during import process

# version tests
{
    my $sheet = t::lib::DataSheet->new(data => []);

    my $schema  = $sheet->schema;
    my $layout  = $sheet->layout;
    my $columns = $sheet->columns;
    $sheet->create_records;

    my $user1 = $schema->resultset('User')->create({
        username => 'test',
        password => 'test',
    });

    my $user2 = $schema->resultset('User')->create({
        username => 'test2',
        password => 'test2',
    });

    my $in = "string1,Last edited time,Last edited by\nFoobar,2014-10-10 12:00,".$user2->id;
    my $import = GADS::Import->new(
        schema   => $schema,
        layout   => $layout,
        user     => $user1,
        file     => \$in,
    );

    $import->process;

    my $record = GADS::Record->new(
        user   => $sheet->user,
        layout => $layout,
        schema => $schema,
    );
    $record->find_current_id(1);
    is($record->createdby->id, $user2->id, "Record created by correct ID");
    is($record->created, '2014-10-10T12:00:00', "Record created datetime correct");
}

# Deleted version of live enumval and tree
foreach my $type (qw/enum tree/)
{
    my $sheet = t::lib::DataSheet->new(data => []);

    my $schema  = $sheet->schema;
    my $layout  = $sheet->layout;
    my $columns = $sheet->columns;
    $sheet->create_records;

    my $val = $type eq 'enum' ? 'foo1' : 'tree1';
    my $enumval = $schema->resultset('Enumval')->search({ value => $val });
    is($enumval->count, 1, "One current $val enumval");
    $enumval->update({ deleted => 1 });
    $schema->resultset('Enumval')->create({
        layout_id => $enumval->next->layout_id,
        value     => $val,
    });

    my $in = $type eq 'enum' ? "enum1\nfoo1" : "tree1\ntree1";
    my $import = GADS::Import->new(
        schema   => $schema,
        layout   => $layout,
        user     => $sheet->user,
        file     => \$in,
    );

    my $current_rs = $schema->resultset('Current');
    is($current_rs->count, 0, "Zero records to begin");
    $import->process;

    my $record = GADS::Record->new(
        user   => $sheet->user,
        layout => $layout,
        schema => $schema,
    );
    $record->find_current_id(1);
    is($record->fields->{$columns->{$type."1"}->id}->as_string, $val, "Deleted enum import successful");
}

my @tests = (
    {
        data      => "string1\nString content",
        option    => undef,
        count_on  => 1,
        count_off => 1,
    },
    {
        data      => "string1\nFoo\nBar,FooBar", # Test for extra invalid values on row
        option    => undef,
        count_on  => 1,
        count_off => 1,
    },
    {
        data      => "string1\nString content",
        option    => 'dry_run',
        count_on  => 0,
        count_off => 1,
    },
    {
        data      => "string1,integer1\nString content,123\n,234",
        option    => 'force_mandatory',
        count_on  => 2,
        count_off => 1,
    },
    {
        data      => "enum1\nfoo1\nfoobar",
        option    => 'blank_invalid_enum',
        count_on  => 2,
        count_off => 1,
    },
    {
        data      => "enum1\nfoo1\nduplicate",
        option    => 'take_first_enum',
        count_on  => 2,
        count_off => 1,
    },
    {
        data      => qq(enum1\nfoo1\n"foo1,foo2"),
        option    => 'split_multiple',
        count_on  => 2,
        count_off => 1,
        written   => {
            Enum => {
                on  => '112', # Enum ID 1 then IDs 1 and 2
                off => '1',
            },
        },
    },
    {
        data      => "string1\nfoo\n0",
        option    => 'ignore_string_zeros',
        count_on  => 2,
        count_off => 2,
        written   => {
            String => {
                on  => 'foo',
                off => 'foo0',
            },
        },
    },
    {
        data      => "integer1\n100\n12.7",
        option    => 'round_integers',
        count_on  => 2,
        count_off => 1,
        written   => {
            Intgr => {
                on  => '10013',
                off => '100',
            },
        },
    },
);

foreach my $test (@tests)
{   ok 1, "Running test $test->{name}";
    my $to = $test->{option} // '';

    foreach my $status (qw/on off/)
    {   my $sheet = make_sheet $sheet_counter++, data => [], multivalue => 1;

        my $user = $schema->resultset('User')->create({
            username => 'test',
            password => 'test',
        });

        my %options;
        $options{$to} = $status eq 'on' if $to;

        if($to eq 'force_mandatory')
        {   $layout->column_update(string1 => { is_optional => 0 });
        }
        elsif($to eq 'take_first_enum')
        {   $layout->column_update(enum1 => { enumvals => [qw/foo1 duplicate duplicate/] };
        }

        my $test_name = length $to ? "with option $to set to $status" : "with no options";
        is $sheet->content->current->row_count, '==', 0, '... no records before import';

        $sheet->import(file => \$test->{data}, %options)->process;

        is $sheet->content->current->row_count, '==', $test->{"count_$status"},
            '... record count after import';

        if(my $written = $test->{written})
        {   foreach my $table (keys %$written)
            {   join '', grep defined,
                    $::db->search($table, {}, { order_by => 'id' })
                       ->get_column('value')->all;

                my $expected = $written->{$table}{$status};
                is $string, $expected, "Correct written value for $test_name";
            }
        }
    }
}

# update tests
my @update_tests = (
    {
        name    => 'Update unique field with string',
        option  => 'update_unique',
        data    => "string1,integer1\nFoo,100\nFoo2,150",
        unique  => 'string1',
        count   => 3,
        results => {
            string1  => 'Foo Bar Foo2',
            integer1 => '100 99 150',
        },
        written => 2,
        errors  => 0,
        skipped => 0,
    },
    {
        name    => 'Update unique field with enum',
        option  => 'update_unique',
        data    => "string1,enum1\nFooBar1,foo1\nFooBar2,foo3",
        unique  => 'enum1',
        count   => 3,
        results => {
            string1 => 'FooBar1 Bar FooBar2',
            enum1   => 'foo1 foo2 foo3',
        },
        written => 2,
        errors  => 0,
        skipped => 0,
        existing_data => [
            {
                string1    => 'Foo',
                enum1      => 'foo1',
            },
            {
                string1    => 'Bar',
                enum1      => 'foo2',
            },
        ],
    },
    {
        name    => 'Update unique field with tree',
        option  => 'update_unique',
        data    => "string1,tree1\nFooBar1,tree1\nFooBar2,tree3",
        unique  => 'tree1',
        count   => 3,
        results => {
            string1 => 'FooBar1 Bar FooBar2',
            tree1   => 'tree1 tree2 tree3',
        },
        written => 2,
        errors  => 0,
        skipped => 0,
        existing_data => [
            { string1    => 'Foo', tree1      => 'tree1' },
            { string1    => 'Bar', tree1      => 'tree2' },
        ],
    },
    {
        name    => 'Update unique field with person',
        option  => 'update_unique',
        data    => qq(string1,person1\nBar,"User1, User1"),
        unique  => 'person1',
        count   => 1,
        results => {
            string1 => 'Bar',
            person1 => 'User1, User1', # 1 values each with commas
        },
        written => 1,
        errors  => 0,
        skipped => 0,
        existing_data => [ { string1 => 'Foo', person1 => 1 } ],
    },
    {
        name    => 'Update unique field with serial',
        option  => 'update_unique',
        data    => qq(string1,Serial\nBar2,1),
        unique  => 'Serial',
        count   => 1,
        results => {
            string1 => 'Bar2',
        },
        written => 1,
        errors  => 0,
        skipped => 0,
        existing_data => [ { string1 => 'Foo' } ],
    },
    {
        name    => 'Skip when existing unique value exists',
        option  => 'skip_existing_unique',
        data    => "string1,integer1\nFoo,100\nFoo2,150",
        unique  => 'string1',
        count   => 3,
        results => {
            string1  => 'Foo Bar Foo2',
            integer1 => '50 99 150',
        },
        written => 1,
        errors  => 0,
        skipped => 1,
    },
    {
        name    => 'No change of value unless blank',
        option  => 'no_change_unless_blank',
        data    => "string1,integer1,date1\nFoo,200,2010-10-10\nBar,300,2011-10-10",
        unique  => 'string1',
        count   => 2,
        results => {
            string1  => 'Foo Bar',
            integer1 => '50 300',
            date1   => '2010-10-10 2011-10-10',
        },
        written => 2,
        errors  => 0,
        skipped => 0,
        existing_data => [
            { string1 => 'Foo', integer1 => 50, date1 => '' },
            { string1 => 'Bar', integer1 => '', date1 => '' },
        ],
    },
    {
        name           => 'Invalid values', # Check we're not writing the record at all
        option         => 'update_unique',
        data           => "ID,integer1,date1,enum1,tree1,daterange1,curval1\n3,XX,,,,,\n3,,201-9,,,,\n3,,,foo4,,,\n3,,,,tree4,,\n3,,,,,2012-10-10 FF 2013-10-10,\n3,,,,,,9",
        unique         => 'ID',
        count          => 1,
        count_versions => 1,
        results => {
            string1    => 'Foo',
            integer1   => '50',
            date1      => '2010-10-10',
            enum1      => 'foo1',
            tree1      => 'tree1',
            daterange1 => '2010-10-10 to 2010-11-10',
            curval1    => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012',
        },
        written => 0,
        errors  => 6,
        skipped => 0,
        existing_data => [
            {
                string1    => 'Foo',
                integer1   => 50,
                date1      => '2010-10-10',
                enum1      => 'foo1',
                tree1      => 'tree1',
                daterange1 => ['2010-10-10', '2010-11-10'],
                curval1    => 1,
            },
        ],
    },
    {
        name           => 'Attempt to update ID from different table',
        option         => 'update_unique',
        data           => "ID,string1\n1,Bar", # ID from curval table
        unique         => 'ID',
        count          => 1,
        count_versions => 1,
        results => { string1 => 'Foo' },
        written => 0,
        errors  => 0,
        skipped => 1,
        existing_data => [ { string1 => 'Foo' } ],
    },
    {
        name           => 'Update existing records only',
        option         => 'update_only',
        data           => "ID,string1,integer1,date1,enum1,tree1,daterange1,curval1\n3,Bar,200,2011-10-10,foo2,tree2,2011-10-10 to 2011-11-10,2\n4,,,,,,,",
        unique         => 'ID',
        count          => 2,
        count_versions => 2,
        calc_code      => '
            function evaluate (_version_user, _version_datetime)
                return _version_user.firstname .. _version_user.surname
                    .. _version_datetime.year .. _version_datetime.month .. _version_datetime.day
            end
        ',
        results => {
            string1    => 'Bar ',
            integer1   => '200 ',
            date1      => '2011-10-10 ',
            enum1      => 'foo2 ',
            tree1      => 'tree2 ',
            daterange1 => '2011-10-10 to 2011-11-10 ',
            curval1    => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008 ',
            calc1      => 'User1User120141010 User1User120141010',
        },
        written => 2,
        errors  => 0,
        skipped => 0,
        existing_data => [
            {
                string1    => 'Foo',
                integer1   => 50,
                date1      => '2010-10-10',
                enum1      => 'foo1',
                tree1      => 'tree1',
                daterange1 => ['2010-10-10', '2010-11-10'],
                curval1    => 1,
            },
            {
                string1    => 'FooBar',
                integer1   => 10,
                date1      => '2010-10-10',
                enum1      => 'foo1',
                tree1      => 'tree1',
                daterange1 => ['2010-10-10', '2010-11-10'],
                curval1    => 1,
            },
        ],
    },
);

my $sheet_counter = 42;
foreach my $test (@update_tests)
{   ok 1, "Running test $test->{name}";

    # Create initial records with this datetime
    set_fixed_time('10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

    my $curval_sheet = make_sheet $sheet_counter++;

    my %extra;
    if(my $t = $test->{calc_code})
    {   $extra{calc_code}        = $t;
        $extra{calc_return_type} = 'string';
    }

    my $sheet  = make_sheet $sheet_counter++,
        curval => $curval_sheet->id,
        data   => $test->{existing_data} || undef,
        %extra;

    my $layout  = $sheet->layout;

    # Then do upload with this datetime. With update_only, previous one
    # should be used
    set_fixed_time('05/05/2015 01:00:00', '%m/%d/%Y %H:%M:%S');

    my $unique_id;
    if(my $u = $test->{unique})
    {   if($u eq 'ID')
        {   $unique_id = $layout->column('_id');
        }
        else
        {   my $unique = $layout->column_by_name($u);
            $layout->column_update($unique, { is_unique => 1 })
                unless $unique->is_internal;
            $unique_id = $unique->id;
        }
    }

    my %options;
    if($test->{option} eq 'update_unique')
    {   $options{update_unique} = $unique_id;
    }

    if($test->{option} eq 'skip_existing_unique')
    {   $options{skip_existing_unique} = $unique_id;
    }

    if($test->{option} eq 'no_change_unless_blank')
    {   $options{update_unique} = $unique_id;
        $options{no_change_unless_blank} = 'skip_new';
    }

    if($test->{option} eq 'update_only')
    {   $options{update_only} = 1;
        $options{update_unique} = $unique_id;
    }

    $sheet->import(file => \$test->{data}, %options)->process;

    my $page   = $sheet->content->current;
    is($page->row_count, $test->{count}, "Correct record count after import test $test->{name}");

    if($test->{count_versions})
    {   my $versions = Linkspace::Row::Revision->revision_count($sheet);
        cmp_ok $versions, '==', $test->{count_versions},
            "Correct version count after import test $test->{name}")
    }

    foreach my $col_name (keys %{$test->{results}})
    {   my $column = $layout->column($col_name);
        my @got    = map $_->cell($col_name)->as_string, @{$page->rows};
        is "@got", $test->{results}{$col_name}, "Correct data written to $col_name";
    }

    my $imp = $schema->resultset('Import')->next;
    cmp_ok $imp->written_count, '==', $test->{written}, '... check written lines';
    cmp_ok $imp->error_count,   '==', $test->{errors},  '... check error lines';
    cmp_ok $imp->skipped_count, '==', $test->{skipped}, '... check skipped lines';
}

done_testing;
