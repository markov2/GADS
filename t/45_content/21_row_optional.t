# Test simplest form of row
# Extracted from t/021_topic.t

use Linkspace::Test
#   not_ready => 'needs revisions'
;

my $sheet   = make_sheet
    columns => [ qw/string intgr enum date/ ];

my $layout  = $sheet->layout;
my $content = $sheet->content;

# date1 and enum1 stay optional
$layout->column_update(string1  => { is_optional => 0 });
like logline, qr/string1' changed fields: optional/, '... log string1 change to optional';

$layout->column_update(integer1 => { is_optional => 0 });
like logline, qr/integer1' changed fields: optional/, '... log integer1 change to optional';

### First try writing the record with the missing values

my $row_count = $content->row_count;

my %cells = ( enum1 => 'foo2' );
my %row   = ( revision => { cells => \%cells });
try { $content->row_create(\%row) };
like $@->wasFatal->message, qr/Column 'L\d+string1' requires a value/,
    'Unable to write with missing 2 values';

cmp_ok $content->row_count, '==', $row_count, '... no new records created';
like logline, qr/Current created/, '... log-lines are not revoked';

### Set one of the values, should be the same result

$cells{string1} = 'Foobar';
try { $content->row_create(\%row) };
like $@->wasFatal->message, qr/Column 'L\d+integer1' requires a value/,
    'Unable to write with missing 1 value';

cmp_ok $content->row_count, '==', $row_count, '... no new records created';
like logline, qr/Current created/, '... log-lines are not revoked';

### Set the second one, should be able to write now

$cells{integer1} = 100;
my $row = $content->row_create(\%row);
ok $row, 'Row written after values completed';

cmp_ok $content->row_count, '==', $row_count +1, '... new row in table';
like logline, qr/Current created/, '... log row created';
like logline, qr/Record created/, '... log revision created';

my $rev = $row->current;
ok defined $rev, 'Checking created revision';
isa_ok $rev, 'Linkspace::Row::Revision', '... ';
is $rev->cell('integer1'), 100,      '... integer1 arrived';
is $rev->cell('string1' ), 'Foobar', '... string1 arrived';
is $rev->cell('enum1'   ), 'foo2',   '... enum1 arrived';

done_testing;
