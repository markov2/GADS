#!/usr/bin/env perl

use strict;
use warnings;

use Log::Report;
use Test::More; # tests => 1;

use t::lib::DataSheet;

use_ok 'Linkspace::Filter::DisplayField';

# Tests to check that fields that depend on another field for their display are
# blanked if they should not have been shown

my $curval_sheet = t::lib::DataSheet->new(instance_id => 2);
$curval_sheet->create_records;

my $sheet   = t::lib::DataSheet->new(
    curval             => 2,
    curval_field_ids   => [ $curval_sheet->columns->{string1}->id ],
    multivalue         => 1,
    multivalue_columns => { string => 1, tree => 1 },
    column_count       => { integer => 2 },
);
$sheet->create_records;

my $layout   = $sheet->layout;
my $string1  = $layout->column('string1');  ok $string1;
my $enum1    = $layout->column('enum1');    ok $enum1;
my $integer1 = $layout->column('integer1'); ok $integer1;

sub _filter
{   my %params = @_;
    my %rule1    = (
        display_field_id => $params{col_id},
        operator => $params{operator} || 'equal',
        regex    => $params{regex},
    );
    Linkspace::Filter::DisplayField->new(
        column     => $column,
        _rule_rows => [ \%rule1 ],
        condition  => undef,
    );
}

$integer1->display_fields(_filter(col_id => $string1->id, regex => 'foobar'));
$integer1->write;

my $row = $sheet->content->find_current_id(3);
sub _field($)   { $row->field($_[0]->id) }
sub _set($$)    { _field($_[0])->set_value($_[1]) }
sub _content($) { _field($_[0])->as_string }

# Initial checks
is _content $string1, 'Foo', 'Initial string value is correct';
is _content $integer1, '50', 'Initial integer value is correct';

my @types = (
    {
        type   => 'equal',
        normal => "foobar",
        blank  => "xxfoobarxx",
    },
    {
        type   => 'contains',
        normal => "xxfoobarxx",
        blank  => "foo",
    },
    {
        type   => 'not_equal',
        normal => "foo",
        blank  => "foobar",
    },
    {
        type   => 'not_contains',
        normal => "foo",
        blank  => "xxfoobarxx",
    },
    {
        type          => 'equal',
        normal        => ['foo', 'bar', 'foobar'],
        string_normal => 'bar, foo, foobar',
        blank         => ["xxfoobarxx", 'abc'],
        string_blank  => 'abc, xxfoobarxx',
    },
    {
        type          => 'contains',
        normal        => ['foo', 'bar', 'xxfoobarxx'],
        string_normal => 'bar, foo, xxfoobarxx',
        blank         => "fo",
    },
    {
        type          => 'not_equal',
        normal        => ['foo', 'foobarx'],
        string_normal => 'foo, foobarx',
        blank         => ['foobar', 'foobar2'],
        string_blank  => 'foobar, foobar2',
    },
    {
        type          => 'not_contains',
        normal        => ['fo'],
        string_normal => 'fo',
        blank         => ['foo', 'bar', 'xxfoobarxx'],
        string_blank  => 'bar, foo, xxfoobarxx',
    },
);

foreach my $test (@types)
{
    my $filter = _filter(col_id => $string1->id, regex => 'foobar', operator => $test->{type}));
    isa_ok $filter, 'Linkspace::Field::DisplayField';
#XXX
    $integer1->display_fields($filter);

    # Test write of value that should be shown
    {   _set $string1->id  => $test->{normal};
        _set $integer1->id => '150';

        is _content $string1, $test->{string_normal} || $test->{normal},
            "Updated string value is correct (normal $test->{type})";

        is _content $integer1, '150'
            "Updated integer value is correct (normal $test->{type})";
    }

    # Test write of value that shouldn't be shown (string)
    {   _set $string1  => $test->{blank};
        _set $integer1 => '200';

        is _content $string1, $test->{string_blank} || $test->{blank},
            "Updated string value is correct (blank $test->{type})";

        is _content $integer1, '',
           "Updated integer value is correct (blank $test->{type})";
    }
}

# Multiple field tests
@types = (
    {
        display_condition => 'AND',
        filters => [
            {
                type  => 'equal',
                field => 'string1',
                regex => 'foobar',
            },
            {
                type  => 'equal',
                field => 'enum1',
                regex => 'foo1',
            },
        ],
        values => [
            {
                normal => {
                    string1 => 'foobar',
                    enum1   => 7,
                },
                blank => {
                    string1 => 'xxfoobarxx',
                    enum1   => 8,
                },
            },
            {
                blank => {
                    string1 => 'foobar',
                    enum1   => 8,
                },
            },
            {
                blank => {
                    string1 => 'xxfoobarxx',
                    enum1   => 7,
                },
            },
        ],
    },
    {
        display_condition => 'OR',
        filters => [
            {
                type  => 'equal',
                field => 'string1',
                regex => 'foobar',
            },
            {
                type  => 'equal',
                field => 'enum1',
                regex => 'foo1',
            },
        ],
        values => [
            {
                normal => {
                    string1 => 'foobar',
                    enum1   => 7,
                },
                blank => {
                    string1 => 'xxfoobarxx',
                    enum1   => 8,
                },
            },
            {
                normal => {
                    string1 => 'foobar',
                    enum1   => 8,
                },
            },
            {
                normal => {
                    string1 => 'xxfoobarxx',
                    enum1   => 7,
                },
            },
        ],
    },
);

foreach my $test (@types)
{
    my @rules = map +{
        display_field_id => $columns->{$_->{field}}->id,
        operator => $_->{type},
        regex    => $_->{regex},
    } @{$test->{filters}};

    my $filter = Linkspace::Field::DisplayField->new(
        column     => $integer1,
        _rule_rows => \@rules,
        condition  => $test->{display_condition},
    );

    foreach my $value (@{$test->{values}})
    {
        # Test write of value that should be shown
        if(my $n = $value->{normal})
        {   _set $string1  => $n->{string1};
            _set $enum1    => $n->{enum1};
            _set $integer1 => '150';

        $row->write(no_alerts => 1);
        $row = $row->find_current_id(3);
            is _content $string1, $test->{string_normal} || $test->{normal},
                "Updated string value is correct (normal $test->{type})");

            is _content $integer1, '150',
                "Updated integer value is correct (normal $test->{type})");
        }

        # Test write of value that shouldn't be shown (string)
        if(my $b = $value->{blank})
        {   _set $string1  => $b->{string1};
            _set $enum1    => $b->{enum1};
            _set $integer1 => '200';

        $row->write(no_alerts => 1);
        $row = $row->find_current_id(3);

            is _content $string1, $test->{string_blank} || $test->{blank},
               "Updated string value is correct (blank $test->{type})";

            is _content $integer1, '',
               "Updated integer value is correct (blank $test->{type})";
        }
    }
}

# Reset
$integer1->display_fields(_filter(col_id => $string1->id, regex => 'foobar', operator => 'equal'));
$integer1->write;

# Test that mandatory field is not required if not shown by regex
{
    $integer1->optional(0);
    $integer1->write;

    _set $string1  => 'foobar';
    _set $integer1 => '';
    try { $record->write(no_alerts => 1) };
    like($@, qr/is not optional/, "Record failed to be written with shown mandatory blank");

    _set $string1  => 'foo';
    _set $integer1 => '';
    try { $record->write(no_alerts => 1) };
    ok !$@, "Record successfully written with hidden mandatory blank";
}

# Test each field type
my @fields = (
    {
        field       => 'string1',
        regex       => 'apples',
        value_blank => 'foobar',
        value_match => 'apples',
    },
    {
        field       => 'enum1',
        regex       => 'foo3',
        value_blank => 8,
        value_match => 9,
    },
    {
        field       => 'tree1',
        regex       => 'tree1',
        value_blank => 11,
        value_match => 10,
    },
    {
        field       => 'integer2',
        regex       => '250',
        value_blank => '240',
        value_match => '250',
    },
    {
        field       => 'curval1',
        regex       => 'Bar',
        value_blank => 1, # Foo
        value_match => 2, # Bar
    },
    {
        field       => 'date1',
        regex       => '2010-10-10',
        value_blank => '2011-10-10',
        value_match => '2010-10-10',
    },
    {
        field       => 'daterange1',
        regex       => '2010-12-01 to 2011-12-02',
        value_blank => ['2011-01-01', '2012-01-01'],
        value_match => ['2010-12-01', '2011-12-02'],
    },
    {
        field       => 'person1',
        regex       => 'User1, User1',
        value_blank => 2,
        value_match => 1,
    },
);

foreach my $field (@fields)
{
    my $col = $columns->{$field->{field}};
    $integer1->display_fields(_filter(col_id => $col->id, regex => $field->{regex}));
    $integer1->write;

    my $row = ...
    _set $col      => $field->{value_blank};
    _set $integer1 => 838;
    try { $record->write(no_alerts => 1) };

    $row = $record->find_current_id($row->current_id);

    is _content $integer1, '',
        "Value not written for blank regex match (column $field->{field})");

    _set $col      => $field->{value_match};
    _set $integer1 => 839;
    try { $record->write(no_alerts => 1) };

    $row = $row->find_current_id($row->current_id);
    is _content $integer1, '839',
        "Value written for regex match (column $field->{field})";
}

# Test blank value match
{
    $integer1->display_fields(_filter(col_id => $string1->id, regex => ''));
    $integer1->write;

    $row = ...
    _set $string1  => '';
    _set $integer1 => 789;
    $record->write(no_alerts => 1);

    $row = $row->find_current_id($row->current_id);
    is _content $integer1, '789',
        "Value written for blank regex match";

    $row = ...
    _set $string1   => 'foo';
    _set $integer1  => 234;
    $record->write(no_alerts => 1);

    $row = $row->find_current_id($row->current_id);
    is _content $integer1, '', "Value not written for blank regex match";
}

# Test value that depends on tree. Full levels of tree values can be tested
# using the nodes separated by hashes
{
    # Set up columns
    my $tree1 = $columns->{tree1};
    $integer1->display_fields(_filter(col_id => $tree1->id, regex => '(.*#)?tree3'));
    $integer1->write;
    $layout->clear;

    $record->clear;
    $record->find_current_id(3);

    # Set value of tree that should blank int
    _set $tree1    => 10; # value: tree1
    _set $integer1 => '250';
    $record->write(no_alerts => 1);

    $record->clear;
    $record->find_current_id(3);

    is _content $tree1,   'tree1', 'Initial tree value is correct';
    is _content $integer1, '', 'Updated integer value is correct';

    # Set matching value of tree - int should be written
    _set $tree1    => 12;
    _set $integer1 => '350';
    $record->write(no_alerts => 1);
    $record->find_current_id(3);

    is _content $tree1    => 'tree3', 'Updated tree value is correct';
    is _content $integer1 => '350', 'Updated integer value is correct';

    # Same but multivalue - int should be written
    _set $tree1    => [10,12];
    _set $integer1 => '360';
    $record->write(no_alerts => 1);
    $record->find_current_id(3);

    is _content $tree1, 'tree1, tree3', 'Updated tree value is correct';
    is _content $integer1, '360', 'Updated integer value is correct';

    # Now test 2 tree levels
    $integer1->display_fields(_filter(col_id => $tree1->id, regex => 'tree2#tree3'));
    $integer1->write;

    # Set matching value of tree - int should be written
    _set $tree1    => 12;
    _set $integer1 => '400';
    $record->write(no_alerts => 1);

    $record->find_current_id(3);

    is _content $tree1, 'tree3', 'Tree value is correct';
    is _content $integer1, '400', 'Updated integer value with full tree path is correct';

    # Same but reversed - int should not be written
    _set $tree1    => 11;
    _set $integer1 => '500';
    $record->write(no_alerts => 1);
    $record->find_current_id(3);

    is _content $tree1, 'tree2', 'Tree value is correct';
    is _content $integer1, '', 'Updated integer value with full tree path is correct';

    # Same, but test higher level of full tree path
    $integer1->display_fields(_filter(col_id => $tree1->id, regex => 'tree2#', operator => 'contains'));
    $integer1->write;
    $record->find_current_id(3);

    # Set matching value of tree - int should be written
    _set $tree1    => 12;
    _set $integer1 => '600';
    $record->write(no_alerts => 1);
    $record->find_current_id(3);

    is _content $tree1, 'tree3', 'Tree value is correct';
    is _content $integer1, '600', 'Updated integer value with full tree path is correct';
}

# Tests for dependent_shown
{
    sub _shown($) { _field($_[0])->dependent_shown }

    $integer1->display_fields(_filter(col_id => $string1->id, regex => 'Foobar'));
    $integer1->write;

    $row = ...
    _set $string1  => 'Foobar';
    _set $integer1 => '100';
    $record->write(no_alerts => 1);

    my $current_id = $record->current_id;
    $record->clear;
    $record->find_current_id($current_id);
    ok _shown $string1,  "String shown in view";
    ok _shown $integer1, "Integer shown in view";

    _set $string1  => 'Foo';
    _set $integer1 => '200';
    $record->write(no_alerts => 1);
    ok _shown $string1, "String still shown in view";
    ok _shown $integer1, "Integer not shown in view";

    _set $string1  => 'Foobarbar';
    _set $integer1 => '200';
    $record->write(no_alerts => 1);
    ok  _shown $string1, "String still shown in view";
    ok !_shown $integer1, "Integer not shown in view";

    # Although dependent_shown is not used in table view, it is still
    # generated as part of the presentation layer
    my $records = GADS::Records->new(
        user   => $sheet->user,
        layout => $layout,
        schema => $schema,
        columns => [$integer1->id],
    );

    while (my $rec = $records->single)
    {
        # Will always be shown as the column it depends on is not in the view
        ok _shown $integer1, "Integer not shown in view";
    }
}

# Tests for recursive display fields
{
    $string1->display_fields(_filter(col_id => $string1->id, regex => 'Foobar'));
    try { $string1->write };
    like($@, qr/not be the same/, "Unable to write display field same as field itself");
}

# Finally check that columns with display fields can be deleted
{
    try { $string1->delete };
    like($@, qr/remove these conditions before deletion/, "Correct error when deleting depended field");
    try { $integer1->delete };
    ok(!$@, "Correctly deleted independent display field");
}

done_testing;
