# Tests to check that a curval field can refer to the same table

use Linkspace::Test;

my $data = [
    { string1 => 'foo1' },
    { string1 => 'foo2' },
];

my $sheet   = make_sheet
    rows => $data;

my $layout  = $sheet->layout;

my $string = $columns->{string1};
# Create another curval fields that would cause a recursive loop. Check that it
# fails
my $curval = GADS::Column::Curval->new(
    schema => $schema,
    user   => $user,
    layout => $layout,
);

my $curval = $sheet->layout->column_create({
    type            => 'curval',
    name            => 'curval1',
    refers_to_sheet => $sheet,
    curval_columns  => [ 'string1' ],
    permissions     => [ $sheet->group => $sheet->default_permissions ],
});
   
my $row1 = $sheet->content->row_create;
$row1->revision_create({ string1 => 'foo3', curval1 => 1 });

my $row1b = $sheet->content->row(3);  # reload
is $row1b->cell('curval1'),  "foo1", "Curval with ID correct";

done_testing;
