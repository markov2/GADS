# Check the Integer column type

use Linkspace::Test;

my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type       => 'intgr',
    name_short => 'column1',
});
ok defined $column1, 'Created column1';

my $path1 = $column1->path;
is $path1, $sheet->path.'/intgr=column1', '... check path';
is logline, "info: Layout created ${\($column1->id)} $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Intgr', '...';

# is_valid_value
