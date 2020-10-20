#!/usr/bin/env perl

use Linkspace::Test
    not_ready => 'Linkspace::Filter::DisplayField';

plan skip_all => 'Waits for cell handling';

# Tests to check that fields that depend on another field for their display are
# blanked if they should not have been shown

my $curval_sheet = make_sheet;

my $sheet   = make_sheet
    curval_sheet       => $curval_sheet,
    curval_columns     => [ 'string1' ],
    multivalue_columns => [ qw/string tree/ ],
    column_count       => { integer => 2 };
my $layout = $sheet->layout;

sub _set_filter($$$)
{   my ($column, $settings, $rules) = @_;
    $layout->column_update($column => { display_field => {
        %$settings,
        rules     => $rules,
    }});
}

#XXX used?
$layout->column_update(string1 => { display_field => { rules => {
    operator => 'equal',
    regex    => 'foobar',
}}});

my $row = $sheet->content->row(3);
sub _cell($)     { $row->cell($_[0]) }
sub _set(@)      { $row->revision_create( { @_ } ) }
sub _contains($) { $row->cell($_[0])->as_string }

# Initial checks
is _contains string1  => 'Foo', 'Initial string value is correct';
is _contains integer1 => '50', 'Initial integer value is correct';

my @tests1 = (
    {
        operator => 'equal',
        normal   => "foobar",
        blank    => "xxfoobarxx",
    },
    {
        operator => 'contains',
        normal   => "xxfoobarxx",
        blank    => "foo",
    },
    {
        operator => 'not_equal',
        normal   => "foo",
        blank    => "foobar",
    },
    {
        operator => 'not_contains',
        normal   => "foo",
        blank    => "xxfoobarxx",
    },
    {
        operator      => 'equal',
        normal        => ['foo', 'bar', 'foobar'],
        string_normal => 'bar, foo, foobar',
        blank         => ["xxfoobarxx", 'abc'],
        string_blank  => 'abc, xxfoobarxx',
    },
    {
        operator          => 'contains',
        normal        => ['foo', 'bar', 'xxfoobarxx'],
        string_normal => 'bar, foo, xxfoobarxx',
        blank         => "fo",
    },
    {
        operator      => 'not_equal',
        normal        => ['foo', 'foobarx'],
        string_normal => 'foo, foobarx',
        blank         => ['foobar', 'foobar2'],
        string_blank  => 'foobar, foobar2',
    },
    {
        operator      => 'not_contains',
        normal        => ['fo'],
        string_normal => 'fo',
        blank         => ['foo', 'bar', 'xxfoobarxx'],
        string_blank  => 'bar, foo, xxfoobarxx',
    },
);

foreach my $test (@tests1)
{   my $op = $test->{operator};
    _set_filter integer1 => { column => 'string1' }, { regex => 'foobar', operator => $op };

    # Test write of value that should be shown
    {   _set string1 => $test->{normal}, integer1 => '150';

        is _contains string1 => $test->{string_normal} || $test->{normal},
            "Updated string value is correct (normal $op)";

        is _contains integer1 => '150',
            "Updated integer value is correct (normal $op)";
    }

    # Test write of value that shouldn't be shown (string)
    {   _set string1 => $test->{blank}, integer1 => '200';

        is _contains string1 => $test->{string_blank} || $test->{blank},
            "Updated string value is correct (blank $op)";

        is _contains integer1 => '',
           "Updated integer value is correct (blank $op)";
    }
}

### Multiple field tests

my @tests2 = (
    {
        display_condition => 'AND',
        filters => [
            { operator => 'equal', column => 'string1', regex => 'foobar' },
            { operator => 'equal', column => 'enum1',   regex => 'foo1' },
        ],
        values => [
          { normal => { string1 => 'foobar',     enum1 => 7 },
            blank  => { string1 => 'xxfoobarxx', enum1 => 8 },
          },
          { blank  => { string1 => 'foobar',     enum1   => 8 } },
          { blank  => { string1 => 'xxfoobarxx', enum1   => 7 } },
        ],
    },
    {
        display_condition => 'OR',
        filters => [
          { operator  => 'equal', column => 'string1', regex => 'foobar' },
          { operator  => 'equal', column => 'enum1',   regex => 'foo1' },
        ],
        values => [
            { normal => { string1 => 'foobar',     enum1 => 7 },
              blank  => { string1 => 'xxfoobarxx', enum1 => 8 },
            },
            { normal => { string1 => 'foobar',     enum1 => 8 } },
            { normal => { string1 => 'xxfoobarxx', enum1 => 7 } },
        ],
    },
);

foreach my $test (@tests2)
{
    $layout->column_update(integer1 => { display_field => {
        _rule_rows => $test->{filters},
        condition  => $test->{display_condition},
    }});

    foreach my $value (@{$test->{values}})
    {
        # Test write of value that should be shown
        if(my $n = $value->{normal})
        {   _set string1 => $n->{string1}, enum1 => $n->{enum1}, integer1 => '150';

            is _contains string1 => $test->{string_normal} || $test->{normal},
                "Updated string value is correct (normal $test->{type})";

            is _contains integer1 => '150',
                "Updated integer value is correct (normal $test->{type})";
        }

        # Test write of value that shouldn't be shown (string)
        if(my $b = $value->{blank})
        {   _set string1 => $b->{string1}, enum1 => $b->{enum1}, integer1 => '200';

            is _contains string1 => $test->{string_blank} || $test->{blank},
               "Updated string value is correct (blank $test->{type})";

            is _contains integer1 => '',
               "Updated integer value is correct (blank $test->{type})";
        }
    }
}

# Reset
_set_filter integer1 => { column => 'string1'}, { regex => 'foobar', operator => 'equal' };

# Test that mandatory field is not required if not shown by regex
{   $layout->column_update(integer1 => { is_optional => 0 });

    try { _set string1 => 'foobar', integer1 => '' };
    like $@, qr/is not optional/,
        'Record failed to be written with shown mandatory blank';

    try { _set string1 => 'foo', integer1 => '' };
    ok !$@, 'Record successfully written with hidden mandatory blank';
}

# Test each field type
my @tests3 = (
    {
        column      => 'string1',
        regex       => 'apples',
        value_blank => 'foobar',
        value_match => 'apples',
    },
    {
        column      => 'enum1',
        regex       => 'foo3',
        value_blank => 8,
        value_match => 9,
    },
    {
        column      => 'tree1',
        regex       => 'tree1',
        value_blank => 11,
        value_match => 10,
    },
    {
        column      => 'integer2',
        regex       => '250',
        value_blank => '240',
        value_match => '250',
    },
    {
        column      => 'curval1',
        regex       => 'Bar',
        value_blank => 1, # Foo
        value_match => 2, # Bar
    },
    {
        column      => 'date1',
        regex       => '2010-10-10',
        value_blank => '2011-10-10',
        value_match => '2010-10-10',
    },
    {
        column      => 'daterange1',
        regex       => '2010-12-01 to 2011-12-02',
        value_blank => ['2011-01-01', '2012-01-01'],
        value_match => ['2010-12-01', '2011-12-02'],
    },
    {
        column      => 'person1',
        regex       => 'User1, User1',
        value_blank => 2,
        value_match => 1,
    },
);

foreach my $test (@tests3)
{   my $column = $test->{column};
    _set_filter integer1 => { column => $column }, { regex => $test->{regex} };

    try { _set $column => $test->{value_blank}, integer1 => 838 };
    is $@, '...';

    is _contains integer1 => '', "Value not written for blank regex match (column $column)";

    _set $column => $test->{value_match}, integer1 => 839;
    is _contains integer1 => '839', "Value written for regex match (column $column)";
}

# Test blank value match
{   _set_filter integer1 => { column => 'string1' }, { regex => '' };

    _set string1 => '', integer1 => 789;
    is _contains integer1 => '789', "Value written for blank regex match";

    _set string1 => 'foo', integer1 => 234;
    is _contains integer1 => '', "Value not written for blank regex match";
}

# Test value that depends on tree. Full levels of tree values can be tested
# using the nodes separated by hashes
{
    _set_filter integer1 => { column => 'tree1' }, { regex => '(.*#)?tree3' };

    # Set value of tree that should blank int
    _set tree1 => 10, integer1 => '250';   # value: tree1
    is _contains tree1    => 'tree1', 'Initial tree value is correct';
    is _contains integer1 => '', 'Updated integer value is correct';

    # Set matching value of tree - int should be written
    _set tree1 => 12, integer1 => '350';
    is _contains tree1    => 'tree3', 'Updated tree value is correct';
    is _contains integer1 => '350', 'Updated integer value is correct';

    # Same but multivalue - int should be written
    _set tree1 => [ 10, 12 ], integer1 => '360';
    is _contains tree1    => 'tree1, tree3', 'Updated tree value is correct';
    is _contains integer1 => '360', 'Updated integer value is correct';

    ###
    ### Now test 2 tree levels
    ###

    _set_filter integer1 => { column => 'tree1' }, { regex => 'tree2#tree3' };

    # Set matching value of tree - int should be written
    _set tree1 => 12, integer1 => '400';
    is _contains tree1    => 'tree3', 'Tree value is correct';
    is _contains integer1 => '400', 'Updated integer value with full tree path is correct';

    # Same but reversed - int should not be written
    _set tree1 => 11, integer1 => '500';
    is _contains tree1    => 'tree2', 'Tree value is correct';
    is _contains integer1 => '', 'Updated integer value with full tree path is correct';

    ###
    ### Same, but test higher level of full tree path
    ###
    _set_filter integer1 => { column => 'tree1' },
      { regex => 'tree2#', operator => 'contains' };

    # Set matching value of tree - int should be written
    _set tree1 => 12, integer1 => '600';
    is _contains tree1    => 'tree3', 'Tree value is correct';
    is _contains integer1 => '600', 'Updated integer value with full tree path is correct';
}

# Tests for dependent_shown
{
    sub _shown($) { _cell($_[0])->dependent_shown }

    _set_filter integer1 => { column => 'string1' }, { regex => 'Foobar'};

    _set string1 => 'Foobar', integer1 => '100';
    ok _shown 'string1',  "String shown in view";
    ok _shown 'integer1', "Integer shown in view";

    _set string1 => 'Foo', integer1 => '200';
    ok _shown 'string1', "String still shown in view";
    ok _shown 'integer1', "Integer not shown in view";

    _set string1  => 'Foobarbar', integer1 => '200';
    ok  _shown 'string1', "String still shown in view";
    ok !_shown 'integer1', "Integer not shown in view";

    # Although dependent_shown is not used in table view, it is still
    # generated as part of the presentation layer
    my $page = $sheet->content->search(columns => [ 'integer1' ]);
    while($row = $page->row_next)
    {   # Will always be shown as the column it depends on is not in the view
        ok _shown 'integer1', "Integer not shown in view";
    }
}

# Tests for recursive display fields
{
    try { _set_filter string1 => { column => 'string1' }, { regex => 'Foobar' } };
    like $@, qr/not be the same/, "Unable to write display field same as field itself";
}

# Finally check that columns with display fields can be deleted
{
    try { $layout->column_delete('string1') };
    like $@, qr/remove these conditions before deletion/,
        "Correct error when deleting depended field";

    { $layout->column_delete('integer1');
    ok "Correctly deleted independent display field";
}

done_testing;
