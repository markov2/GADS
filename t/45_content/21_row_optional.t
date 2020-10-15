# Test simplest form of row
# Extracted from t/021_topic.t

use Linkspace::Test
#   not_ready => 'needs revisions'
;

my $sheet   = make_sheet
    columns => [ qw/string integer enum date/ ];

my $layout  = $sheet->layout;
my $content = $sheet->content;

# date1 and enum1 stay optional
$layout->column_update(string1  => { is_optional => 0 });
$layout->column_update(integer1 => { is_optional => 0 });

### First try writing the record with the missing values

my $row_count = $content->row_count;

my %revision = ( enum1 => 'foo2' );
try { $content->row_create( { revision => \%revision } ) };
like $@, qr/until the following fields have been completed.*string1.*integer1/,
    'Unable to write with missing values';

cmp_ok $content->row_count, '==', $row_count, 'No new records created';

### Set one of the values, should be the same result

$revision{string1} = 'Foobar';
try { $content->row_create( { revision => \%revision } ) };
like $@, qr/until the following fields have been completed.*integer1/,
    'Unable to write with missing values';

### Set the second one, should be able to write now

$revision{integer1} = 100;
my $row = try { $content->row_create( { revision => \%revision } ) };
ok $row, 'Row written after values completed';

cmp_ok $content->row_count, '==', $row_count +1, 'new record in table';

my $rev = $row->current;
is $rev->cell('integer1'), 100,      '... integer1 arrived';
is $rev->cell('string1' ), 'Foobar', '... string1 arrived';
is $rev->cell('enum1'   ), 'foo2',   '... enum1 arrived';

### Now blank a value, shouldn't be able to write again

my %update = ( integer1 => '' );
try { $row->revision_update(\%update) };
like $@, qr/until the following fields have been completed.*integer1/,
    'Unable to write with missing values';

# Remove enum value, should write
$update{enum1} = '';
$row->revision_update(\%update);
ok 1, 'Written record after setting dependent value to blank';  #XXX ????

done_testing;
