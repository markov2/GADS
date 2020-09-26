use Linkspace::Test;

my $sheet   = test_sheet multivalues => 1;
my $layout  = $sheet->layout;

sub _records
{   my ($user, $count) = @_;
    cmp_ok $sheet->content->nr_rows, '==', $count, "Check number of records in retrieved dataset";
    @{$results->rows} if defined wantarray;
}

ok ! $layout->has_children, "Layout does not have children initially";

my $row1 = _records($sheet->user, 2)->[0];

# Create child

try {
    # First try writing without selecting any unique values. Should bork.
    $sheet->content->child_row_create({
        user       => $sheet->user,
        parent_row => $row1,     #XXX id is current_id
    });
};
ok $@, "Failed to write child record with no unique columns defined";

# Only set unique daterange. Should affect daterange field and dependent calc

$layout->colomn_update(daterange1 => { can_child => 1 });
ok $layout->has_children, "Layout has children after creating child column";

my $child_row = $sheet->content->child_row_create({
    user       => $sheet->user,
    parent_row => $row1,
    cells      => { daterange1 => ['2011-10-10','2015-10-10'] },
});

### Force refetch of everything from database

# test_sheet defaults to two rows... we added one
my ($parent, $other, $child) = _records($sheet->user, 3);

isnt $parent->cell('daterange1'), $child->cell('daterange1'),
    "Parent and child date ranges are different";

is $parent->cell('calc1'), 2012, "Parent calc value is correct after first write";
is $child->cell('calc1'),  2011, "Child calc value is correct after first write";

is $parent->cell($_), $child->cell($_), "Parent and child $_ are the same";
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
    "Parent and child date ranges are different";

is $parent2->cell('calc1'), 2000, "Parent calc value is correct after second write";
is $child2->cell('calc1'),  2011, "Child calc value is correct after second write";

is $parent2->cell($_), $child2->cell($_), "Parent and child $_ are the same"
    for qw/string1 enum1 tree1 date1/;

# Same as parent even though DR different
is $child2->cell('rag1'), 'b_red', "Child rag is red";

### Test multivalue field
# First, a second value

$parent2->cell_update(enum1 => [ 2, 3 ]);
my ($parent3, $other3, $child3) = _records($sheet->user, 3);

is $parent3->cell('enum1'), $child3->cell('enum1'), "Parent and child enums are the same";

# And second, back to a single value
$parent3->cell_update(enum1 => 3);
my ($parent4, $other4, $child4) = _records($sheet->user, 3);
is $parent4->cell('enum1'), $child4->cell('enum1'), "Parent and child enums are the same";


# Now change unique field and check values
$layout->column_update(daterange1 => { can_child => 0 });
$layout->column_update(string1 => { can_child => 1 });

$child4->cell_update(string1 => foo3);
my ($parent5, $other5, $child5) = _records($sheet->user, 3);

is $parent5->cell('daterange1'), $child5->cell('daterange1'), "Parent and child date ranges are the same";
is $parent5->cell('calc1'), 2000, "Parent calc value is correct after writing new daterange to parent after child unique change";
is $child5->cell('calc1'),  2000, "Child calc value is correct after removing daterange as unique";

isnt $parent5->cell('string1'), $child5('string1'), "Parent and child strings are different";
is   $parent5->cell('rag1'), $child5->cell('rag1'), "Parent and child rags are the same";

# Set new daterange value in parent, check it propagates to child calc and
# alerts set correctly. Run 2 tests, one with a calc value that is different in
# the child, and one that is the same
$ENV{GADS_NO_FORK} = 1;
foreach my $calc_depend (0..1)
{
    my $code = $calc_depend
        ? "function evaluate (L1string1, L1integer1) \n return string.sub(L1string1, 1, 3) .. L1integer1 \n end"
        : "function evaluate (L1string1) \n return 'XX' .. string.sub(L1string1, 1, 3) \n end";

    my $sheet = t::lib::DataSheet->new(
        rows             => [ { string1  => 'Foo', integer1 => 50 } ],
        calc_code        => $code,
        calc_return_type => 'string',
    );
    my $layout  = $sheet->layout;

    my $string1 = $columns->{string1};
    my $string1_id = $string1->id;
    if ($calc_depend)
    {
        $columns->{string1}->set_can_child(1);
        $columns->{string1}->write;
    }
    else {
        $columns->{integer1}->set_can_child(1);
        $columns->{integer1}->write;
    }
    my $calc1_id = $columns->{calc1}->id;
    $layout->clear;

    my $parent = GADS::Record->new(
        schema => $schema,
        layout => $layout,
        user   => $sheet->user,
    );
    my $parent_id = 1;
    $parent->find_current_id($parent_id);
    my $v = $calc_depend ? 'Foo50' : 'XXFoo';
    is($parent->fields->{$calc1_id}, $v, 'Initial double calc correct');

    my $child = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $child->parent_id($parent->current_id);
    $child->initialise;
    if ($calc_depend)
    {
        $child->fields->{$string1_id}->set_value('Bar');
    }
    else {
        # Doesn't really matter what we write here for these tests
        $child->fields->{$columns->{integer1}->id}->set_value(100);
    }
    $child->write;
    my $child_id = $child->current_id;
    $child->clear;
    $child->find_current_id($child_id);
    $v = $calc_depend ? 'Bar50' : 'XXFoo';
    is($child->fields->{$calc1_id}, $v, 'Calc correct for child record');

    my $view = GADS::View->new(
        name        => 'view1',
        instance_id => 1,
        layout      => $layout,
        schema      => $schema,
        user        => $sheet->user,
        global      => 1,
        columns     => [$calc1_id],
    );
    $view->write;

    # Calc field can be different in child, so should see child in view
    my $records = GADS::Records->new(
        user   => $sheet->user,
        layout => $layout,
        schema => $schema,
        view   => $view,
    );
    my $count = $calc_depend ? 2 : 1;
    is($records->count, $count, "Correct parent and child in view");

    my $alert = GADS::Alert->new(
        user      => $sheet->user,
        layout    => $layout,
        schema    => $schema,
        frequency => 24,
        view_id   => $view->id,
    );
    $alert->write;

    is( $schema->resultset('AlertSend')->count, 0, "Correct number");

    $parent->fields->{$string1_id}->set_value('Baz');
    $parent->write;

    is( $schema->resultset('AlertSend')->count, $count, "Correct number");
    $schema->resultset('AlertSend')->delete;

    # Set new string value in parent but one that doesn't affect calc value
    $parent->clear;
    $parent->find_current_id($parent_id);
    $parent->fields->{$string1_id}->set_value('Bazbar');
    $parent->write;
    is( $schema->resultset('AlertSend')->count, 0, "Correct number");

    # And now one that does affect it
    $parent->fields->{$string1_id}->set_value('Baybar');
    $parent->write;
    is( $schema->resultset('AlertSend')->count, $count, "Correct number");
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

    is($child->parent_id, $parent_id, "Child record has correct parent ID");
    my $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, "Parent record has correct child ID");

    # Then single record_id
    $child->clear;
    $child->find_record_id($child_record_id);
    $parent->clear;
    $parent->find_record_id($parent_record_id);

    is($child->parent_id, $parent_id, "Child record has correct parent ID");
    $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, "Parent record has correct child ID");

    # Now as bulk retrieval
    ($parent, $other, $child) = _records($sheet->user, 3);
    is($child->parent_id, $parent_id, "Child record has correct parent ID");
    $chid = pop @{$parent->child_record_ids};
    is($chid, $child_id, "Parent record has correct child ID");
}

# Check update of child record that has been deleted
{
    my $parent_id        = $parent->current_id;
    my $child_id         = $child->current_id;

    my $parent = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $parent->find_current_id($parent_id);

    # Write field to parent, should be copied to child
    $parent->fields->{$columns->{date1}->id}->set_value('1980-10-05');
    $parent->write(no_alerts => 1);
    my $child = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $child->find_current_id($child_id);
    # Check child
    is($child->fields->{$columns->{date1}->id}, '1980-10-05', "Child value correctly written by parent");

    # Delete child
    $child->delete_current;

    # Set parent again
    $parent->clear;
    $parent->find_current_id($parent_id);
    $parent->fields->{$columns->{date1}->id}->set_value('1985-10-05');
    $parent->write(no_alerts => 1);

    # Check child and parent
    $child->clear;
    $child->find_current_id($child_id, deleted => 1);
    is($child->fields->{$columns->{date1}->id}, '1980-10-05', "Deleted child record has not been updated");
    $parent->clear;
    $parent->find_current_id($parent_id);
    is($parent->fields->{$columns->{date1}->id}, '1985-10-05', "Parent updated correctly");

    # Undelete for future tests
    $child->restore;
}

# Check that child record can be retrieved directly even if no child fields
{
    my $child_id = $child->current_id;

    foreach my $col ($layout->all(exclude_internal => 1))
    {
        $col->set_can_child(0);
        $col->write;
    }

    $layout->clear;
    my $string1 = $layout->column_by_name('string1');

    my $child = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $child->find_current_id($child_id);
    is($child->fields->{$string1->id}, "foo3", "Child record successfully retrieved with child fields");

    # Update child record (via parent) even if no child fields
    my $parent_id = $parent->current_id;
    my $parent = GADS::Record->new(
        user     => $sheet->user,
        layout   => $layout,
        schema   => $schema,
    );
    $parent->find_current_id($parent_id);
    $parent->fields->{$string1->id}->set_value('Foobar');
    $parent->write(no_alerts => 1);
    $child->clear;
    $child->find_current_id($child_id);
    is($child->fields->{$string1->id}, "Foobar", "Child record successfully retrieved with child fields");
}

done_testing();
