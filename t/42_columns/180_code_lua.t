  
use Linkspace::Test;

use Linkspace::Column::Code::Lua qw/lua_parse lua_validate/;
use utf8;

my $sheet  = make_sheet columns => [ 'string' ], rows => [];
my $layout = $sheet->layout;

### lua_parse

ok 1, "Check parser";

# the code is already validated, so should always work.

is_deeply [ lua_parse 'function evaluate (_id) return "test" end' ],
   [ ' return "test" ', [ '_id' ] ], '... one parameter';

is_deeply [ lua_parse 'function evaluate (_id, _serial) return "test" end' ],
   [ ' return "test" ', [ '_id', '_serial' ] ], '... two parameters';

is_deeply [ lua_parse 'function evaluate () return "test" end' ],
   [ ' return "test" ', [ ] ], '... no parameters';

### lua_validate

ok 1, "Check errors";

my $column2 = $layout->column_create({
    type          => 'calc',
    name          => 'column2 (long)',
    name_short    => 'column2',
});
logline;

try { lua_validate $sheet, 'function evaluate (_id) return "test“test" end' };
like $@->wasFatal, qr/^error: Extended characters are not supported/,
    '... calc code with invalid character';

try { lua_validate $sheet, 'function (_id) end' };
like $@->wasFatal, qr/^error: Invalid code: must contain function evaluate(...)/,
    '... calc code is not a lua function';

try { lua_validate $sheet, 'function evaluate (xyz) return "tic" end' };
like $@->wasFatal, qr/^error: Unknown short column name 'xyz' in calculation/,
    '... calc code with unknown column';


my $sheet2 = empty_sheet;
$sheet2->layout->column_create({type => 'string', name_short => 'toc'});
logline;

try { lua_validate $sheet, 'function evaluate (toc) return "tic" end' };
is $@->wasFatal, "error: It is only possible to use columns from sheet sheet 1; 'toc' is on sheet 2.\n",
    '... calc code with column on other sheet';

done_testing;

