# Test integer datums
  
use Linkspace::Test;

my %dummy_file_data =    # from ::Test::Sheet
  ( name     => 'myfile.txt',
    mimetype => 'text/plain',
    content  => 'My text file',
  );

my $sheet = make_sheet columns => [ 'file' ];
ok defined $sheet, 'Sheet with column "file1"';

my $content = $sheet->content;

my $row_ids = $content->row_ids;
cmp_ok scalar @$row_ids, '==', 2, '... hash two default rows';

#### checks on first cell

my $column1 = $sheet->layout->column('file1');
ok defined $column1, '... testing columnn file1';

my $cell1 = $sheet->cell($row_ids->[0], $column1);
ok defined $cell1, 'File on first row';

my $datums1 = $cell1->datums;
cmp_ok scalar @$datums1, '==', 1, '... contains one datum';

my $file1 = $datums1->[0];
ok defined $file1, '... datum is defined';
isa_ok $file1, 'Linkspace::Datum::File', '...';

is $file1->name,     $dummy_file_data{name},     '... filename correct';
is $file1->mimetype, $dummy_file_data{mimetype}, '... mimetype correct';

#!!!! Requires additional db-access when used after file_meta
is $file1->content,  $dummy_file_data{content},  '... content correct';

####

my $results1 = $column1->resultset_for_values;
ok defined $results1, 'Resultset';
cmp_ok scalar @$results1, '==', 1, '... deduplicated';
is $results1->[0]->name, $dummy_file_data{name}, '... right filename';


done_testing;
