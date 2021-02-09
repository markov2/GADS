# Test integer datums
  
use Linkspace::Test;
use Scalar::Util qw(refaddr);

my $dummy_person = $::session->user;   # from ::Test::Sheet

my $sheet = make_sheet columns => [ 'person' ];
ok defined $sheet, 'Sheet with column "person1"';

my $content = $sheet->content;

my $row_ids = $content->row_ids;
cmp_ok scalar @$row_ids, '==', 2, '... hash two default rows';

#### checks on first cell

my $column1 = $sheet->layout->column('person1');
ok defined $column1, '... testing columnn person1';

my $cell1 = $sheet->cell($row_ids->[0], $column1);
ok defined $cell1, 'Person on first row';

my $datums1 = $cell1->datums;
cmp_ok scalar @$datums1, '==', 1, '... contains one datum';

my $person1 = $datums1->[0];
ok defined $person1, '... datum is defined';
isa_ok $person1, 'Linkspace::Datum::Person', '...';

is $person1->person_id, $dummy_person->id, '... right person';
is refaddr($person1->person), refaddr($dummy_person), '... same object';

my $for_code = $person1->_value_for_code;
is ref $for_code, 'HASH', 'Values for CODE';
is $for_code->{surname}, 'Doe', '... surname';
is $for_code->{text}, 'Doe, John', '... text';
is $for_code->{department}, 'My Dept', '... department';
is $for_code->{organisation}, 'My Orga', '... organisation';

done_testing;
