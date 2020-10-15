use Linkspace::Test
    not_ready => 'much rewrite to do';

my $sheet   = make_sheet multivalues => 1;
my $layout  = $sheet->layout;
my $content = $sheet->content;

sub _records
{   my ($user, $count) = @_;
    cmp_ok $content->row_count, '==', $count,
       'Check number of records in retrieved dataset';
    @{$results->rows} if defined wantarray;
}

ok ! $layout->has_children, 'Layout does not have children initially';

my $row1 = _records($sheet->user, 2)->[0];

# Create child

try {
    # First try writing without selecting any unique values. Should bork.
    $row1->child_create;
};
ok $@, 'Failed to write child record with no unique columns defined';

# Only set unique daterange. Should affect daterange field and dependent calc

$layout->colomn_update(daterange1 => { can_child => 1 });
ok $layout->has_children, 'Layout has children after creating child column';

my $child_row = $row1->child_create({
    cells => { daterange1 => ['2011-10-10','2015-10-10'] },
});

### Force refetch of everything from database

# test_sheet defaults to two rows... we added one
my ($parent, $other, $child) = _records($sheet->user, 3);

isnt $parent->cell('daterange1'), $child->cell('daterange1'),
    'Parent and child date ranges are different';

is $parent->cell('calc1'), 2012, 'Parent calc value is correct after first write';
is $child->cell('calc1'),  2011, 'Child calc value is correct after first write';

is $parent->cell($_), $child->cell($_), 'Parent and child $_ are the same';
    for qw/string1 enum1 tree1 date1 rag1/;

### Now update parent daterange and strings and check relevant changes in child

$row->revision_create({
    daterange1 => ['2000-01-01', '2000-02-02'],
    string1    => 'foo2',
    enum1      => 1,
    tree1      => 5,
    date1      => '2017-04-05',
});

# And fetch records again for testing

my ($parent2, $other2, $child2) = _records($sheet->user, 3);

isnt $parent2->cell('daterange1'), $child2->cell('daterange1'),
    'Parent and child date ranges are different';

is $parent2->cell('calc1'), 2000, 'Parent calc value is correct after second write';
is $child2->cell('calc1'),  2011, 'Child calc value is correct after second write';

is $parent2->cell($_), $child2->cell($_), 'Parent and child $_ are the same'
    for qw/string1 enum1 tree1 date1/;

# Same as parent even though DR different
is $child2->cell('rag1'), 'b_red', 'Child rag is red';

### Test multivalue field
# First, a second value

$parent2->cell_update(enum1 => [ 2, 3 ]);
my ($parent3, $other3, $child3) = _records($sheet->user, 3);

is $parent3->cell('enum1'), $child3->cell('enum1'), 'Parent and child enums are the same';

# And second, back to a single value
$parent3->cell_update(enum1 => 3);
my ($parent4, $other4, $child4) = _records($sheet->user, 3);
is $parent4->cell('enum1'), $child4->cell('enum1'), 'Parent and child enums are the same';


# Now change unique field and check values
$layout->column_update(daterange1 => { can_child => 0 });
$layout->column_update(string1 => { can_child => 1 });

$child4->cell_update(string1 => foo3);
my ($parent5, $other5, $child5) = _records($sheet->user, 3);

is $parent5->cell('daterange1'), $child5->cell('daterange1'), 'Parent and child date ranges are the same';
is $parent5->cell('calc1'), 2000, 'Parent calc value is correct after writing new daterange to parent after child unique change';
is $child5->cell('calc1'),  2000, 'Child calc value is correct after removing daterange as unique';

isnt $parent5->cell('string1'), $child5('string1'), 'Parent and child strings are different';
is   $parent5->cell('rag1'), $child5->cell('rag1'), 'Parent and child rags are the same';

# Set new daterange value in parent, check it propagates to child calc and
# alerts set correctly. Run 2 tests, one with a calc value that is different in
# the child, and one that is the same
$ENV{GADS_NO_FORK} = 1;
foreach my $calc_depend (0..1)
{
    if($cal_depend)
    {   $code = 'function evaluate (L1string1, L1integer1) \n return string.sub(L1string1, 1, 3) .. L1integer1 \n end';
        $column = 'string1';
        $calc_initial = 'Foo500';
        $value        = 'Bar';
        $calc_child   = 'Bar50';
        $view_expected = 2;
    }
    else
    {   $code = 'function evaluate (L1string1) \n return 'XX' .. string.sub(L1string1, 1, 3) \n end';
        $column = 'integer1';
        $calc_initial = 'XXFoo';
        $value  = 100;            # value does not matter
        $calc_child   = 'XXFoo';
        $view_expected = 1;
    }

    my $sheet = make_sheet
        rows             => [ { string1  => 'Foo', integer1 => 50 } ],
        calc_code        => $code,
        calc_return_type => 'string',
    );
    my $layout  = $sheet->layout;

    $layout->column_update($column => { can_child => 1 });

    my $parent_id = 1;
    my $parent = $sheet->content->row($parent_id);

    is $parent->cell('calc1'), $calc_initial, 'Initial double calc correct';

    my $child = $sheet->content->row_create({ parent_row => $parent });
    is $child->cell('calc1'), $calc_child, 'Calc correct for child record';

    my $view = $sheet->views->view_create({
        name        => 'view1',
        columns     => [ 'calc1' ],
        is_global   => 1,
    );

    # Calc field can be different in child, so should see child in view

    my $results = $sheet->content->search(view => $view);
    is $results->count, $view_expected, 'parent and child in view';

    my $alerts = $sheet->alerts;
    my $alert  = $alerts->alert_create(24, $view);

    cmp_ok $alerts->alerts_sent_count, '==', 0, '... no alerts sent yet';
    $parent->revision_create({ string1 => 'Baz' });

    cmp_ok $alerts->alerts_sent_count, '==', $view_expected, '... alerts sent';
    $alerts->remove_alerts_send;

    # Set new string value in parent but one that doesn't affect calc value
    $parent->revision_create({ string1 => 'Bazbar' });
    cmp_ok $alerts->alerts_sent_count, '==', 0, '... no alerts sent yet';

    # And now one that does affect it
    $parent->revision_create({ string1 => 'Baybar' });
    cmp_ok $alerts->alerts_sent_count, '==', $view_expected, '... alerts sent';
}

# Check that each record's parent/child IDs are correct
{
    my $parent_id        = $parent->current_id;
    my $child_id         = $child->current_id;
    my $parent_record_id = $parent->current_id;
    my $child_record_id  = $child->current_id;

    # First as single fetch
    my $child = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $child->find_current_id($child_id);

    my $parent = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $parent->find_current_id($parent_id);

    is($child->parent_id, $parent_id, 'Child record has correct parent ID');
    my $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, 'Parent record has correct child ID');

    # Then single record_id
    $child->clear;
    $child->find_record_id($child_record_id);
    $parent->clear;
    $parent->find_record_id($parent_record_id);

    is($child->parent_id, $parent_id, 'Child record has correct parent ID');
    $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, 'Parent record has correct child ID');

    # Now as bulk retrieval
    ($parent, $other, $child) = _records($sheet->user, 3);
    is($child->parent_id, $parent_id, 'Child record has correct parent ID');
    $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, 'Parent record has correct child ID');
}

# Check update of child record that has been deleted
{
    my $parent_id        = $parent->current_id;
    my $child_id         = $child->current_id;

    my $parent1 = $sheet->content->row($parent_id);
    $parent1->revision_create( { date1 => '1980-10-05'} );

    my $child1 = $sheet->content->row($child_id);
    is $child1->cell('date1'), '1980-10-05', 'Child value correctly written by parent';

    # Delete child
    $sheet->content->row_delete($child1);

    # Set parent again
    my $parent1b = $sheet->content->row($parent_id);  #XXX ? needed
    $parent1b->revision_create( { date1 => '1980-10-05'} );

    # Check child and parent
    my $$child1b = $sheet->content->row($child_id, include_deleted => 1);
    is $child1b->cell('date1'), '1980-10-05', 'Deleted child record has not been updated';

    my $parent1c = $sheet->content->row($parent_id);  #XXX ? needed
    is $parent->cell('date1'), '1980-10-05', 'Parent updated correctly';

    # Undelete for future tests
    $child->restore;
}

# Check that child record can be retrieved directly even if no child fields
{
    $layout->column_update($_ => { can_child => 0 })
         for $layout->all(exclude_internal => 1);

    my $child = $sheet->content->row($child_id);
    is $child->cell('string1'), 'foo3', 'Child record successfully retrieved with child fields';

    # Update child record (via parent) even if no child fields

    $sheet->content->row($parent)->revision_create({ string1 => 'Foobar' });

    my $child2 = $sheet->content->row($child_id);  # reload
    is $child2->cell('string1'), 'Foobar', 'Child record successfully retrieved with child fields';
}

done_testing;
