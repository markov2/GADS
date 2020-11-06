# Test the creation activity of the sheet layout

use Linkspace::Test;

my $sheet = test_site->document->sheet_create({ name => 'sheet 1' });

is logline, "info: Instance created ${\$sheet->id}: ${\$sheet->path}",
        '... logged creation of sheet '.$sheet->path;


my $layout = $sheet->layout;
ok defined $layout, 'Sheet contains layout';

is $sheet->layout, $layout, '... cache layout object';

### Check initial columns

cmp_ok @{$layout->columns_search(exclude_internal => 1)}, '==', 0, '... no own columns';
my $internals = $layout->columns_search;

cmp_ok @$internals, '==', 7, '... found all expected internals';

is $layout->as_string(exclude_internal => 0), <<'__INTERNALS', '... as string';
 1 id          I  U _id
 2 createddate I    _version_datetime
 3 createdby   I O  _version_user
 4 createdby   I O  _created_user
 5 deletedby   I    _deleted_by
 6 createddate I    _created
 7 serial      I  U _serial
__INTERNALS

like logline, qr/Layout create.*=_/, '... internal creation logged'
     for @$internals;

cmp_ok @{$layout->columns_search(only_internal => 1)}, '==', @$internals, '... same count';

### Collect a column

my $id_col = $layout->column('_id');
ok defined $id_col, 'Find column by name';
isa_ok $id_col, 'Linkspace::Column', '... ';
isa_ok $id_col, 'Linkspace::Column::Id', '... ';

my $id_col2 = $layout->column($id_col->id);
ok defined $id_col2, '... by id';
is $id_col2, $id_col, '... same';

### Add a column

my $column1 = $layout->column_create({ type => 'intgr', name_short => 'i1' });
ok defined $column1, 'Create a column';
isa_ok $column1, 'Linkspace::Column::Intgr', '... ';
my $col1_id = $column1->id;

is logline, "info: Layout created $col1_id: ".$column1->path;

is $column1->name_short, 'i1', '... check name_short';
is $column1->name, 'i1', '... check name';
is $column1->position, @$internals+1, '... position';

my $column1b = Linkspace::Column->from_id($col1_id);
ok defined $column1b, '... reloaded from db by id';
isa_ok $column1b, 'Linkspace::Column::Intgr', '... ... ';
isnt $column1b, $column1, '... ... different object';
is $column1b->name_short, $column1->name_short, '... ... same name';

cmp_ok @{$layout->columns_search(exclude_internal => 1)}, '==', 1, '... one own column';

try { $layout->column_create({ type => 'intgr', name_short => 'i1' }) };
is $@->wasFatal,
    "error: Attempt to create a second column with the same short name 'i1'\n",
    '... refuse double names';

### Add a second column

my $column2 = $layout->column_create({ type => 'intgr', name_short => 'i2' });
ok defined $column2, 'Create second column';
is $column2->position, @$internals+2, '... position';
is logline, "info: Layout created ${\($column2->id)}: ".$column2->path;

cmp_ok @{$layout->columns_search(exclude_internal => 1)}, '==', 2, '... two own columns';

TODO: { local $TODO = "waiting for other internal types";
is $layout->as_string(exclude_internal => 1), <<'__AS_STRING', '... as_string';
 8 intgr            i1
 9 intgr            i2
__AS_STRING
}

try { $layout->column_update($column2, { name_short => $column1->name_short }) };
is $@->wasFatal,
   "error: Attempt to rename column 'i2' into existing name 'i1'\n",
   '... refuse to rename into existing';

### Reposition

ok $layout->reposition( [qw/i2 i1 _id/] ), 'Repositioning columns';
my $pos_base = @$internals-1;
is $layout->column('i2')->position, $pos_base+1, '... i2 now first';
is $layout->column('i1')->position, $pos_base+2, '... before i1';
is $layout->column('_id')->position, $pos_base+3, '... before _id';

cmp_ok logs(), '==', @$internals+2, '... everyone changed position';

diag "More testing to do";

#TODO: max_width
#TODO: column_delete

done_testing;
