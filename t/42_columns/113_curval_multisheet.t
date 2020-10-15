# Rewrite of t/004_multisheet.t
# Only use multivalue for the referenced sheet. Normal multivalue is tested elsewhere.

use Linkspace::Test
   not_ready => 'waiting for curval';

my $curval_sheet = make_sheet columns => [ qw/string1 enum1/ ];
my $curval_layout = $curval_sheet->layout;

my $sheet1 = make_sheet
    rows             => [],
    multivalues      => 1,
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1', 'enum1' ];
my $layout1 = $sheet1->layout;

my $sheet2 = make_sheet
    rows             => [],
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1', 'enum1' ];
my $layout2 = $sheet2->layout;

# Set link field of second sheet daterange to daterange of first sheet
$layout2->column_update($_ => { link_parent => $layout1->column($_) })
   for qw/daterange1 enum1 curval1/;

my $row1 = $sheet1->content->row_create;
$row1->revision_create({
   daterange1 => ['2010-10-10', '2012-10-10'],
   enum1      => [ 7 ],
   curval1    => [ 1 ],
});

my $row2 = $sheet2->content->row_create;
$row2->revision_create({
   daterange1 => [ '2010-10-15', '2013-10-10' ],
   enum1      => [ 13 ],
   curval1    => [ 2 ],
});

# Clear the record object and write a new one, this time with the
# date blank but linked to the first sheet with a date value

my $row3 = $sheet2->content->row_create;
$row3->revision_create({
   linked     => $row1,
   string1    => 'Foo',
});

###!!! all filters are applied to $sheet2
sub _link($$)
{   my ($parent, $child) = @_;
    $sheet2->column($parent) . '_' . $sheet1->column($child);
}

my @filters = (
    {
        name  => 'Basic - ascending',
        rules => [{
            column   => 'daterange1',
            operator => 'contains',
            value    => '2011-10-10',
        }],
        sort   => 'asc',
        values => [
            'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010;',
            'string1: ;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-15 to 2013-10-10;file1: ;person1: ;curval1: Bar, foo2;rag1: b_red;calc1: 2010;',
        ],
        count => 2,
    },
    {
        name  => 'Basic - descending',
        rules => [{
            column   => 'daterange1',
            operator => 'contains',
            value    => '2011-10-10',
        }],
        sort   => 'desc',
        values => [
            'string1: ;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-15 to 2013-10-10;file1: ;person1: ;curval1: Bar, foo2;rag1: b_red;calc1: 2010;',
            'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010;',
        ],
        count => 2,
    },
    {
        name  => 'Curval search of ID in parent record',
        rules => [{
            column   => 'curval1',
            type     => 'string',
            operator => 'equal',
            value    => '1',
        }],
        sort   => 'desc',
        values => [
            'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010;',
        ],
        count => 1,
    },
    {
        name  => 'Curval search of ID in main record',
        rules => [{
            column   => 'curval1',
            type     => 'string',
            operator => 'equal',
            value    => '2',
        }],
        sort   => 'desc',
        values => [
            'string1: ;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-15 to 2013-10-10;file1: ;person1: ;curval1: Bar, foo2;rag1: b_red;calc1: 2010;',
        ],
        count => 1,
    },
    {
        name  => 'Curval search of string sub-field in parent record',
        rules => [{
            id       => _link(curval1 => 'string1'),
            type     => 'string',
            value    => 'Foo',
            operator => 'equal',
        }],
        sort   => 'desc',
        values => [
            'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010;',
        ],
        count => 1,
    },
    {
        name  => 'Curval search of enum sub-field in parent record',
        rules => [{
            id       => _link(curval1 => 'enum1'),
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        }],
        sort   => 'desc',
        values => [
            'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010;',
        ],
        count => 1,
    },
);

my @columns2 = sort { $a->id <=> $b->id } $sheet2->layout->all_colums;

foreach my $filter (@filters)
{
    my $rules = {
        rules     => $filter->{rules},
        condition => $filter->{condition},
    };

    my $view = $sheet2->views->view_create({
        name         => $filter->{name},
        filter       => $rules,
        columns      => \@columns2,
        sort_columns => [ 'daterange1' ],
        sort_order   => [ $filter->{sort} ],
    });
    ok defined $view, "Running filter $filter->{name}";

    my $results = $sheet2->content->search({ view => $view });
    cmp_ok $results->count, '==', $filter->{count}, '... count';

    foreach my $expected (@{$filter->{values}})
    {   my $row = $results->next_row;
        my @got  = map $_->name.': ' . $row->cell($_) . ';', @columns2;
        is join('', @got), $expected, "... data ID ". $row->current_id;
    }
}

# Retrieve single record and check linked values
my $row4 = $sheet2->content->row($row2->current_id);
my $got  = join ";", map $_->name.': ' . $row4->cell($_), @columns2;

my $expected = 'string1: Foo;integer1: ;enum1: foo1;tree1: ;date1: ;daterange1: 2010-10-10 to 2012-10-10;file1: ;person1: ;curval1: Foo, foo1;rag1: b_red;calc1: 2010';

is $got, $expected, "Retrieve record with linked field by current ID";

my $row4b = $sheet2->content->row_revision($row2->current->id);
$got = join ";", map $_->name.': ' . $row4->cell($_), @columns2;
is $got, $expected, "Retrieve record with linked field by record ID";

done_testing;
