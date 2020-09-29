
use Linkspace::Test;

my $data = [
    {
        string1    => 'Foo',
        date1      => '2013-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        integer1   => 10,
        enum1      => 'foo1',
        curval1    => 1,
    },
];

my $curval_sheet = make_sheet 2, rows => [];

my $sheet        = make_sheet 1,
   curval_sheet => $curval_sheet,
   rows         => $data;

my $layout = $sheet->layout;
my $columns = $sheet->columns;
$sheet->create_records;

# Set up an autocur field that only shows a field that is not unique between
# parent and child. Normally the child would not be shown in these
# circumstances, but we do want it to be for an autocur so that all related
# records are shown.
my $autocur1 = $curval_sheet->layout->column_create({
    type            => 'autocur',
    refers_to_sheet  => $sheet,
    related_field    => 'curval1',
    curval_columns   => [ 'integer1' ],
);

my $parent = $sheet->content->search->row(1);

# Set up field with child values
$layout->column_update(string1 => { can_child => 1 });

my $row2 = $layout->content->row_create({ parent => $parent });
$row2->revision_create({string1 => 'Foobar');

my $results = $sheet->content->search;
cmp_ok $results->count, '==', 2, "Parent and child records exist";

my $curval_row = $curval_sheet->content->row(1);
is $curval_row->cell($autocur1), "10; 10", "Autocur value correct";

done_testing;
