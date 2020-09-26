use Linkspace::Test;

my @data2 = (
    {
        string1    => 'Foo',
        integer1   => '100',
        enum1      => [7, 8],
        tree1      => 10,
        date1      => '2010-10-10',
        daterange1 => ['2000-10-10', '2001-10-10'],
        curval1    => 1,
        file1      => undef, # Add random file
    },
    {
        string1    => 'Bar',
        integer1   => '200',
        enum1      => 8,
        tree1      => 11,
        date1      => '2011-10-10',
        daterange1 => ['2000-11-11', '2001-11-11'],
        curval1    => 2,
        file1      => undef,
    },
);

my @data3 = (
    {
        string1    => 'Foo',
        integer1   => 50,
        date1      => '2014-10-10',
        daterange1 => ['2012-02-10', '2013-06-15'],
        enum1      => 1,
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        daterange1 => ['2008-05-04', '2008-07-14'],
        enum1      => 2,
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        daterange1 => ['2008-05-04', '2008-07-14'],
        enum1      => '',
    },
    {
        string1    => 'FooBar',
        integer1   => 150,
        date1      => '2000-01-02',
        daterange1 => ['2001-05-12', '2002-03-22'],
        enum1      => 3,
    },
);

my $curval_sheet = make_sheet '2', data => \@data3;
my $sheet   = make_sheet '1',
    rows             => \@data2,
    multivalues      => 1,
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1' ],
    calc_code        => "function evaluate (L1string1)
        if type(L1string1) == \"table\" then
            L1string1 = L1string1[1]
        end
        return L1string1
    end",
    calc_return_type => 'string',
);


# Various tests for field types
#
# Code

try { my $calc = $layout->column_update(calc1 => {
   code => 'function evaluate (_id) return "test“test" end'
})  };
ok $@->wasFatal, "Failed to write calc code with invalid character";

# Curval tests
#
# First check that we cannot delete a record that is referred to

try { $sheet->content->row(1)->purge };
like $@, qr/The following records refer to this record as a value/,
   "Failed to purge record in a curval";

my $user = $sheet->user_normal1;
my $curval = $columns->{curval1};

cmp_ok @{$curval->filtered_values}, '==', 4,
   "Correct number of values for curval field (filtered)";

cmp_ok @{$curval->all_values}, '==', 4,
   "Correct number of values for curval field (all)";

# Create a second curval sheet, and check that we can link to first sheet
# (which links to second)
my $curval_sheet2 = make_sheet '4',
    curval => 1,
    curval_offset => 12,
    rows  => 1;

cmp_ok @{$curval_sheet2->column('curval1')->filtered_values}, '==, 2,
    "Correct number of values for curval field";

# Add a curval field without any columns. Check that it doesn't cause fatal
# errors when building values.
# This won't normally be allowed, but we want to test anyway just in case - set
# an env variable to allow it.
$ENV{GADS_ALLOW_BLANK_CURVAL} = 1;

my $curval_blank = $layout->add_column({
    type             => 'curval',
    name             => 'curval blank',
    refers_to_sheet  => $curval_sheet,
    curval_field_ids => [],
    permissions => { $sheet->group->id => $sheet->default_permissions },
)};

# Now force the values to be built. This should not bork
try { $layout->column($curval_blank->id)->filtered_values };
ok !$@, "Building values for curval with no fields does not bork";

# Check that an undefined filter does not cause an exception.  Normally a blank
# filter would be written as an empty JSON string, but that may not be there
# for columns from old versions
my $curval_blank_filter = $layout->add_column({
    name             => 'curval blank',
    type             => 'curval',
    refers_to_sheet  => $curval_sheet,
    curval_field_ids => [],
    permissions => { $sheet->group->id => $sheet->default_permissions },
});

# Manually blank the filters
$schema->resultset('Layout')->update({ filter => undef });

# Now force the values to be built. This should not bork
try { $layout->column($curval_blank_filter->id)->filtered_values };
ok( !$@, "Undefined filter does not cause exception during layout build" );

# Check that we can add and remove curval field IDs
my $field_count = $schema->resultset('CurvalField')->count;
my $curval_add_remove = $layout->add_column({
    name             => 'curval fields',
    type             => 'curval',
    refers_to_sheet  => $curval_sheet->layout->instance_id,
    curval_fields   => [ 'string1' ],
    permissions => { $sheet->group->id => $sheet->default_permissions },
});

is($schema->resultset('CurvalField')->count, $field_count + 1, "Correct number of fields after new");

$layout->column_update($curval_add_remove, { curval_fields => ['string1', 'integer1'] });

is($schema->resultset('CurvalField')->count, $field_count + 2, "Correct number of fields after addition");
$layout->clear;

$layout->column_update($curval_add_remove, { curval_fields => ['integer1'] });
is($schema->resultset('CurvalField')->count, $field_count + 1, "Correct number of fields after removal");

$layout->column_delete($curval_add_remove);


# Filter on curval tests
my $curval_filter = $layout->create_column({
    name     => 'curval filter',
    type     => 'curval',
    filter   => { rule {
        column   => 'string1',
        type     => 'string',
        operator => 'equal',
        value    => 'Foo',
    },
    refers_to_sheet => $curval_sheet,
    curval_columns  => [ 'integer1' ], # Purposefully different to previous tests
    permissions     => { $sheet->group->id => $sheet->default_permissions },
);

# Clear the layout to force the column to be build, and also to build
# dependencies properly in the next test

cmp_ok @{$curval_filter->filtered_values}, '==', 1,
    "Correct number of values for curval field with filter (filtered)";

cmp_ok @{$curval_filter->all_values}, '==', 4,
    "Correct number of values for curval field with filter (all)";

# Create a record with a curval value, change the filter, and check that the
# value is still set for the legacy record even though it no longer includes that value.
# This test also checks that different multivalue curvals (with different
# selected fields) behave as expected (multivalue curvals are fetched
# separately).

my $first_value  = $curval_filter->filtered_values->[0];
my $curval_id    = $first_value->{id};
my $curval_value = $first_value->{value};

my $row = $sheet->content->search->row(1);
$row->cell_update($curval_filter => $curval_id);

$layout->column_update($curval_filter => { filter => { rules => {
    column   => 'string1',
    type     => 'string',
    value    => 'Bar',
    operator => 'equal',
}}});

isnt $curval_filter->filtered_values->[0]->{id}, $curval_id,
    "Available curval values has changed after filter change";

my $cur_id = $record->current_id;
my $row = $record->find_current_id($cur_id);
my $cell = $row->cell($curval_filter);
is $cell->id, $curval_id, "Curval value ID still correct after filter change";
is $cell->as_string, $curval_value, "Curval value still correct after filter change");

# Same again for multivalue (values are retrieved later using a Records search)

$layout->column_update($curval_filter => { is_multivalue => 1 });
my $row   = $sheet->content->search->row(1);
my $datum = $row->cell($curval_filter)->datum;
is $datum->ids->[0], $curval_id, "Curval value ID still correct after filter change (multiple)";
is $datum->as_string, $curval_value, "Curval value still correct after filter change (multiple)";
is $datum->for_code->[0]{field_values}{L2enum1},i
    'foo1', "Curval value for code still correct after filter change (multiple)";

# Add view limit to user
my $autocur1 = $curval_sheet->layout->column_creat({
    type            => 'autocur',
    refers_to_sheet => $sheet,
    related_field   => 'curval1',
);

{
    $layout->user($user); # Default sheet layout user is superadmin. Change to normal user
    $curval_sheet->layout->user($user); # Default sheet layout user is superadmin. Change to normal user

    cmp_ok @{$curval_filter->filtered_values}, '==', 2,
        "Correct number of filted values for curval before view_limit";

    # Add a view limit
    my $rules = { rule => {
        column   => 'enum1',
        type     => 'string',
        operator => 'equal',
        value    => 'foo2',
    }};

    my $view_limit = $curval_sheet->views->view_create({
        name        => 'Limit to view',
        filter      => $rules,
    });

    $user->set_view_limits([ $view_limit ]);

    cmp_ok @{$curval_filter->filtered_values}, '==', 1,
        "Correct number of filtered values after view_limit applied";

    cmp_ok @{$curval_filter->all_values}, '==', 1,
        "Correct number of values after view_limit applied (all)";

    # Check that an override ignores the view_limit  #XXX
    $curval_filter->override_permissions(1);

    $curval_filter = $layout->column($curval_filter->id);
    cmp_ok @{$curval_filter->filtered_values}, '==', 2,
        "Correct number of values for curval field with filter (filtered)";

    # Add view limit to main table and check autocur values.
    # The curval refers to records that this user does not have access to, so
    # it should return a blank value
    my $filter = { rule => {
        column   => 'enum1',
        type     => 'string',
        value    => 'foo3', # Nothing matches, should be no autocur values
        operator => 'equal',
    }};

    $view_limit = $sheet->views->view_create({
        name        => 'Limit to view',
        filter      => $filter,
    });
    $user->set_view_limits([ $view_limit ]);

    my $row = $curval_sheet->content->row($curval_id);
    is $row->cell($autocur1)->as_string, '', "Autocur with limited record not shown";

    # Return to normal for remainder of tests
    $user->set_view_limits([]);
}

# Check that we can filter on a value in the record
$layout->reposition(qw/integer1 date1 daterange1 enum1 tree1 curval1/, 
    $curval_filter, 'string1'/);

# Add multi-value calc for filtering tests
my $calc2 = $sheet->layout->create_column({
    name          => 'calc2',
    name_short    => 'L1calc2',
    return_type   => 'string',
    code          => qq(function evaluate (_id, L1date1, L1daterange1) \n return {"Foo", "Bar"} \nend),
    is_multivalue => 1,
    permissions => { $sheet->group->id => $sheet->default_permissions },
});

# Add display field for filtering tests

my $filter = {
    condition => undef,
    rule      => {
        column   => 'string1',
        operator => 'equal',
        value    => 'Foo',
}};

$layout->column_update(date1 => { display_fields => $filter });

$date1->write;

foreach my $test (qw/string1 enum1 calc1 multi negative nomatch invalid calcmulti displayfield/)
{
    my $field
      = $test =~ /(string1|enum1|calc1)/ ? $test
      : $test eq 'calcmulti'             ? 'string1'
      : $test =~ /(multi|negative)/      ? 'enum1'
      : $test eq 'displayfield'          ? 'date1'
      :                                    'string1';

    my $match = $test =~ /(string1|enum1|calc1|multi|negative)/ ? 1 : 0;
    my $value
      = $test eq 'calc1'        ? '$L1calc1'
      : $test eq 'calcmulti'    ? '$L1calc2'
      : $match                  ? "\$L1$field"
      : $test eq 'nomatch'      ? '$L1tree1'
      : $test eq 'displayfield' ? '$L1date1'
      :                           '$L1string123';

    my $rules = $test eq 'multi'
        ? {
            rules => [
                {
                    column   => $field,
                    type     => 'string',
                    operator => 'equal',
                    value    => $value,
                },
                {
                    column   => $field,
                    type     => 'string',
                    operator => 'is_empty',
                },
            ],
            condition => 'OR',
        }
        : $test eq 'negative'
        ? {
            rule => {
                column   => $field,
                type     => 'string',
                operator => 'not_equal',
                value    => $value,
            },
        }
        : $test eq 'calc1'
        ? {
            rule => {
                column   => 'string1',
                type     => 'string',
                operator => 'equal',
                value    => $value,
            },
        }
        : $test eq 'calcmulti'
        ? {
            rule => {
                column   => 'string1',
                type     => 'string',
                operator => 'equal',
                value    => $value,
            },
        }
        : $test eq 'displayfield'
        ? {
            rule => {
                column   => 'date1',
                type     => 'string',
                operator => 'greater',
                value    => $value,
            },
        }
        : {
            rule => {
                column   => $field,
                type     => 'string',
                operator => 'equal',
                value    => $value,
            }],
        };

    $curval_filter->filter($rules);
    $curval_filter->curval_fields([ 'string1' ]);
    $curval_filter->write;
    $curval_filter->clear;

    my $input_required
        = $test eq 'displayfield' ? 2
        : $test eq 'calcmulti'    ? 3 # date1, daterange1, plus string1 which date1 is a display condition of
        : $test eq 'invalid'      ? 0
        :                           1;

    cmp_ok @{$curval_filter->subvals_input_required}, '==', $input_required,
        "Correct number of input fields required for $test";

    # Clear the layout to force the column to be build, and also to build
    # dependencies properly in the next test
    $layout->clear;

    my $record = $sheet->content->row(5);

    # Hack to make it look like the dependent datums for the curval filter have been written to
    my $written_field = $field eq 'calc1' ? 'string1' : $field;
    my $datum = $record->cell($written_field);
    $datum->oldvalue($datum->clone);
    $record->write(
        dry_run           => 1,
        missing_not_fatal => 1,
        submitted_fields  => $curval_filter->subvals_input_required,
    );
    my $count
      = $test eq 'multi'            ? 3
      : $test eq 'negative'         ? 2
      : $test eq 'displayfield'     ? 1
      : $match && $field eq 'enum1' ? 2
      : $match                      ? 1
      :                               0;

    cmp_ok @{$curval_filter->filtered_values}, '==', $count,
        "Correct number of values for curval field with $field filter, test $test";

    # Check that we can create a new record with the filtered curval field in
    $layout->clear;
    my $record_new = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $record_new->initialise;
    my $cv = $layout->column($curval_filter->id);
    $count
      = $test eq 'multi'            ? 1
      : $test eq 'negative'         ? 3
      : $test eq 'calcmulti'        ? 3
      : $match && $field eq 'enum1' ? 1
      : $match                      ? 0
      :                               0;

    cmp_ok @{$layout->column($curval_filter)->filtered_values}, '==' $count,
        "Correct number of values for curval field with filter";

    $curval_filter->delete;
}

# Now check that we're not building all curval values when we're just
# retrieving individual records
$ENV{PANIC_ON_CURVAL_BUILD_VALUES} = 1;

my $results = $sheet->content->search;

ok $_->field($curval)->text, "Curval field of record has a textual value"
    for @{$page->rows};


# Test deletion of columns in first datasheet. But first, remove curval field
# that refers to this one
$curval_sheet2->columns->{curval1}->delete;
# And autocur
$autocur1->delete;
foreach my $col (reverse $layout->all(order_dependencies => 1))
{
    my $col_id = $col->id;
    my $name   = $col->name;
    ok( $schema->resultset('Layout')->find($col_id), "Field $name currently exists in layout table");
    try { $col->delete };
    is( $@, '', "Deletion of field $name did not throw exception" );
    # Check that it's actually gone
    ok( !$schema->resultset('Layout')->find($col_id), "Field $name has been removed from layout table");
}

done_testing;
