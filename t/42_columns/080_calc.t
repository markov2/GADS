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

### Check compile-time errors

ok 1, "Check errors";

my $column2 = $layout->column_create({ type => 'calc', name_short => 'column2' });
logline;

try { $layout->column_update($column2 => { return_type => 'unknown' }) };
like $@->wasFatal, qr/^error: Unsupported return type 'unknown' for calc column/,
     "... unknown return type";


try { $layout->column_update($column2 => { code => 'function (_id) end' }) };
like $@->wasFatal, qr/^error: Invalid /,
     "... lua validation enabled";

### Check creation of run-time errors

my $column3 = $layout->column_create({ type => 'calc', name_short => 'column3' });
logline;

$layout->column_update($column3 => { code => 'function evaluate (_id) [ end' });
ok 1, "Try run-time error";

my $row = $sheet->content->row_create({ revision => {} });
ok defined $row, '... created empty row in the sheet';
like logline, qr!/row=!, '... ... logged creation row';
like logline, qr!/rev=!, '... ... logged creation revision';

my $rev = $row->current;
ok defined $rev, '... take revision';

try { $rev->cell('column3')->value };
like $@->wasFatal, qr/syntax error/, '... code has syntax error';


### Check processing on request

my $produce_int = "function evaluate()\n return 42 \nend";
my $column4 = $layout->column_create({ type => 'calc', name_short => 'column4',
   return_type => 'integer', code => $produce_int});
logline;
 
is $column4->return_type, 'integer', 'Try to return integer';
is $column4->value_field, 'value_int', '... value in value_int';
is $column4->error_field, 'value_numeric', '... errors in value_numeric';
is $column4->code, $produce_int, '... code accepted';
is $rev->cell($column4)->value, 42, '... calculated code';

my $val4 = $::db->get_record(Calcval => { layout_id => $column4->id, record_id => $rev->id });
ok defined $val4, '... found stored datum';
isa_ok $val4, 'GADS::Schema::Result::Calcval', '... ';

done_testing;
