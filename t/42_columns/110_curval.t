# Check the Curval column type

use Linkspace::Test;

my $sheet   = make_sheet rows => [], columns => [];
my $layout  = $sheet->layout;

my $curval_sheet = make_sheet columns => [ 'intgr' ],
  rows => [ { intgr1 => 42 }, { intgr1 => 43 } ];

my $column1 = $layout->column_create({
    type           => 'curval',
    name           => 'column1 (long)',
    name_short     => 'column1',
    related_column => $curval_sheet->layout->column('intgr1'),
});

ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/curval=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Curval', '...';

is $column1->as_string, <<'__STRING', '... as string';
curval           column1
__STRING

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
isa_ok $column1d, 'Linkspace::Column::Curval', '...';

is $sheet->debug, <<__SHEET, '... debug';
__SHEET

#
# is_valid_value
#

done_testing;
