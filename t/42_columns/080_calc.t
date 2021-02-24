# Check the Calc column type

use Linkspace::Test;
#   not_ready => 'to be implemented';

use utf8;

my $sheet  = empty_sheet;
my $layout = $sheet->layout;

my $column1 = $layout->column_create({
    type          => 'calc',
    name          => 'column1 (long)',
    name_short    => 'column1',
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/calc=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Calc', '...';

### by short_name from cache
my $column1b = $layout->column('column1');
ok defined $column1b, 'Reload via name';
is $column1b->id, $col1_id;

### by id from cache
my $column1c = $layout->column($col1_id);
ok defined $column1b, 'Reload via id';
is $column1b->id, $col1_id,'... loaded with id';

### low level instantiate to avoid the cache
my $column1d = Linkspace::Column->from_id($column1->id, sheet => $sheet);
isnt $column1d, $column1, 'recreated object';
ok defined $column1d, 'Reload via id, avoiding cache';
isa_ok $column1d, 'Linkspace::Column::Calc', '...';

### Errors

ok 1, "Check errors";

my $column2 = $layout->column_create({
    type          => 'calc',
    name          => 'column2 (long)',
    name_short    => 'column2',
});
logline;

try { $layout->column_update($column2 =>
    { code => 'function evaluate (_id) return "test“test" end' }) };
like $@->wasFatal, qr/^error: Extended characters are not supported/,
    "... calc code with invalid character";

try { $layout->column_update($column2 =>
    { code => 'function (_id) end' }) };
like $@->wasFatal, qr/^error: Invalid code: must contain function evaluate(...)/,
    "... calc code is not a lua function";

try { $layout->column_update($column2 => { return_type => 'unknown' }) };
like $@->wasFatal, qr/^error: Unsupported return type 'unknown' for calc column/,
     "... unknown return type";

done_testing;
