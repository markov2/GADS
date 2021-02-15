#!/usr/bin/env perl
# Tests originate from t/003_display_field.t

use Linkspace::Test;

# Tests to check that fields that depend on another field for their display are
# blanked if they should not have been shown

my $curval_sheet = make_sheet;

my $sheet   = make_sheet
#   curval_columns     => [ $curval_sheet->layout->column('string1') ],
    multivalue_columns => [ qw/string tree/ ],
    column_count       => { integer => 2 };

my $layout = $sheet->layout;

sub _set_filter($$$)
{   my ($column, $condition, $filter) = @_;
    $layout->column_update($column => {
        display_filter    => $filter,
        display_condition => $condition,
    });

    like logline, qr/^info: Layout .* changed /, '... filter changed: '.
        $sheet->column($column)->display_filter->as_text;
}

#XXX Maybe standard shortcuts in the future
my $row = $sheet->content->first_row;
sub _cell($)     { $row->current->cell($_[0]) }
sub _contains($) { (_cell $_[0])->as_string }

sub _newrev(@)
{   $row->revision_create({cells => { @_ }});
    like logline, qr/^info: Record created/, 'New revision created';
}

# Initial checks
is _contains string1  => 'Foo', 'Initial string value';
is _contains integer1 =>   50,  'Initial integer value';

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
    _set_filter integer1 => AND =>
       { monitor => 'string1', value => 'foobar', operator => $op};

    # Test write of value that should be shown
    {   _newrev string1 => $test->{normal}, integer1 => '150';

        is _contains string1 => $test->{string_normal} || $test->{normal},
            "... string value normal $op";

        is _contains integer1 => '150', "... integer value normal $op";
    }

    # Test write of value that shouldn't be shown (string)
    {   _newrev string1 => $test->{blank}, integer1 => '200';

        is _contains string1 => $test->{string_blank} || $test->{blank},
            "... string value blank $op";

        is _contains integer1 => '', "... integer value blank $op";
    }
}

### Multiple rules tests

ok 1, 'Tests with multiple rules';

my @tests2 = (
    {
        display_condition => 'AND',
        filters => [
            { monitor => 'string1', operator => 'equal', value => 'foobar' },
            { monitor => 'enum1',   operator => 'equal', value => 'foo1' },
        ],
        values => [
          { normal => { string1 => 'foobar',     enum1 => 'foo1' },
            blank  => { string1 => 'xxfoobarxx', enum1 => 'foo2' },
          },
          { blank  => { string1 => 'foobar',     enum1 => 'foo2' } },
          { blank  => { string1 => 'xxfoobarxx', enum1 => 'foo1' } },
        ],
    },
    {
        display_condition => 'OR',
        filters => [
          { monitor => 'string1', operator  => 'equal', value => 'foobar' },
          { monitor => 'enum1',   operator  => 'equal', value => 'foo1' },
        ],
        values => [
            { normal => { string1 => 'foobar',     enum1 => 'foo1' },
              blank  => { string1 => 'xxfoobarxx', enum1 => 'foo2' },
            },
            { normal => { string1 => 'foobar',     enum1 => 'foo2' } },
            { normal => { string1 => 'xxfoobarxx', enum1 => 'foo1' } },
        ],
    },
);

foreach my $test (@tests2)
{   my $cond = $test->{display_condition};
    _set_filter integer1 => $cond => $test->{filters};

    foreach my $value (@{$test->{values}})
    {
        # Test write of value that should be shown
        if(my $n = $value->{normal})
        {   _newrev string1 => $n->{string1}, enum1 => $n->{enum1}, integer1 => '150';
            is _contains string1 => $n->{string1}, "... string shown (normal $cond)";
            is _contains integer1 => '150', "... integer shown (normal $cond)";
        }

        # Test write of value that shouldn't be shown (string)
        if(my $b = $value->{blank})
        {   _newrev string1 => $b->{string1}, enum1 => $b->{enum1}, integer1 => '200';
            is _contains string1  => $b->{string1}, "... string not shown (blank $cond)";
            is _contains integer1 => '', "... integer not shown (blank $cond)";
        }
    }
}

### Test that mandatory field is not required if not shown by value

{   ok 1, 'Mandatory field not required if not shown';

    _set_filter integer1 => AND =>
        { monitor => 'string1', value => 'foobar', operator => 'equal' };

    $layout->column_update(integer1 => { is_optional => 0 });
    like logline, qr/^info: Layout .* changed fields: optional/, '... set required';

    try { _newrev string1 => 'foobar', integer1 => '' };
    like $@, qr/requires a value/, '... failed to be written with shown mandatory blank';

    try { _newrev string1 => 'foo', integer1 => '' };
    like logline, qr/^info: Record created /, '... revision did get created.';

    ok !$@, '... successfully written with hidden mandatory blank';
}

### Test each field type

my @tests3 = (
    {
        monitor     => 'string1',
        value       => 'apples',
        value_blank => 'foobar',
        value_match => 'apples',
    },
    {
        monitor     => 'enum1',
        value       => 'foo3',
        value_blank => 'foo2',
        value_match => 'foo3',
    },
    {
        monitor     => 'tree1',
        value       => 'tree1',
        value_blank => 'tree2',
        value_match => 'tree1',
    },
    {
        monitor     => 'integer2',
        value       => 250,
        value_blank => 240,
        value_match => 250,
    },
    {
        monitor     => 'curval1',
        value       => 'Bar',
        value_blank => 'Foo',
        value_match => 'Bar',
    },
    {
        monitor     => 'date1',
        value       => '2010-10-10',
        value_blank => '2011-10-10',
        value_match => '2010-10-10',
    },
    {
        monitor     => 'daterange1',
        value       => '2010-12-01 to 2011-12-02',
        value_blank => ['2011-01-01', '2012-01-01'],
        value_match => ['2010-12-01', '2011-12-02'],
    },
    {
        monitor     => 'person1',
        value       => test_user->fullname,
        value_blank => (make_user 1),
        value_match => (test_user),
    },
);

foreach my $test (@tests3)
{   my $monitor = $test->{monitor};
    ok 1, "Testing field $monitor";

if($monitor eq 'curval1') { diag "$monitor not yet supported"; next }

    _set_filter integer1 => AND =>
         { monitor => $monitor, operator => 'equal', value => $test->{value} };

    _newrev $monitor => $test->{value_blank}, integer1 => 838;
    is _contains integer1 => '', "... not written for blank value match";

    #warn $sheet->debug(show_history => 1);

    _newrev $monitor => $test->{value_match}, integer1 => 839;
    is _contains integer1 => 839, "... written for matching value";
}

# Test blank value match

{   ok 1, "Value must be blank";
    _set_filter integer1 => AND => { monitor => 'string1', operator => 'equal', value => '' };

    _newrev string1 => '', integer1 => 789;
    is _contains integer1 => '789', "... yes, blank: do write";

    _newrev string1 => 'foo', integer1 => 234;
    is _contains integer1 => '', "... no, not blank: no write";
}

# Test value that depends on tree. Full levels of tree values can be tested
# using the nodes separated by hashes
{
    #XXX it's quite confusing that the column is named 'tree1', and the
    #XXX values are 'tree1', 'tree2', and 'tree3'.

    ok 1, 'Depends on a tree';  #XXX The regex is equivalent to 'tree3'
    _set_filter integer1 => AND => { monitor => 'tree1', operator => 'contains', value => '(.*#)?tree3' };

    # Set value of tree that should blank int
    _newrev tree1 => 'tree1', integer1 => '250';   # value: tree1
    is _contains tree1    => 'tree1', '... new tree value with tree1';
    is _contains integer1 => '', '... mismatch blanked integer';

    # Set matching value of tree - int should be written
    _newrev tree1 => 'tree3', integer1 => '350';
    is _contains tree1    => 'tree3', '... new tree value with tree3';
    is _contains integer1 => '350', '... match changed integer';

    # Same but multivalue - int should be written
    _newrev tree1 => [ 'tree1', 'tree3' ], integer1 => '360';
    is _contains tree1    => 'tree1, tree3', '... new tree multivalue';
    is _contains integer1 => '360', '... match changed integer';

    #### Now test 2 tree levels

    _set_filter integer1 => AND => { monitor => 'tree1', operator => 'equal', value => 'tree2#tree3' };

    # Set matching value of tree - int should be written
    _newrev tree1 => 'tree3', integer1 => '400';
    is _contains tree1    => 'tree3', '... new tree long path';
    is _contains integer1 => '400', '... match changed integer';

    # Same but reversed - int should not be written
    _newrev tree1 => 'tree2', integer1 => '500';
    is _contains tree1    => 'tree2', '... new tree long path';
    is _contains integer1 => '', '... mismatch blanked integer';

    #### Same, but test higher level of full tree path

    _set_filter integer1 => AND => { monitor => 'tree1', operator => 'contains', value => 'tree2#'};

    # Set matching value of tree - int should be written
    _newrev tree1 => 'tree3', integer1 => '600';
    is _contains tree1    => 'tree3', '... new tree longer path';
    is _contains integer1 => '600', '... match changed integer';
}

#### Tests reading cells for is_displayed

#XXX to avoid awkward work-arounds for displaying historical records, it's better to
#XXX not put this is_displayed() check in opening the cell, but only during data search.

#### Finally check that columns with display fields can be deleted

{   ok 1, 'Removal of monitored columns';

    _set_filter integer1 => AND => { monitor => 'string1', operator => 'contains', value => 'tic'};

    try { $layout->column_delete('string1') };
    like $@, qr/remove these display rules first/, '... error when deleting depended column';

    $layout->column_delete('integer1');
    ok 1, '... can delete independent column';
    like logline, qr/info: Layout .*=integer1' deleted/;
}

done_testing;
