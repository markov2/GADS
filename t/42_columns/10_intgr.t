# Check the Integer column type

use Linkspace::Test;

my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type       => 'intgr',
    name_short => 'column1',
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/intgr=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Intgr', '...';

### by short_name from cache
# $column1b = $sheet->layout->column('column1')
# ok defined $column1, 'Reload via name';
# is $column1b->id, $col1_id;

### by id from cache
# $column1c = $sheet->layout->column($col1_id);

### low level instantiate to avoid the cache
# $column1d => Linkspace::Column->from_id(column1->id, sheet => ..., ??meer??)
# isa Linkspace::Column::Intgr

# is_valid_value
# export_hash

done_testing;
