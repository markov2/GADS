# Test the creation of test sheets
#
# The content of the test-sheet is fixes, with historical (GADS) compatible
# values, to be able to recycle old test scripts.

use Linkspace::Test;
use utf8;

### Empty sheet

my $sheet1 = make_sheet rows => [], columns => [];
ok defined $sheet1, 'Create empty test sheet';

cmp_ok @{$sheet1->layout->columns_search(exclude_internal => 1)}, '==', 0, '... no columns';
cmp_ok $sheet1->content->row_count, '==', 0, '... no rows';

is $sheet1->debug(all => 1), <<__EMPTY_SHEET, '... debug empty sheet';
Sheet ${\$sheet1->id}=sheet 1, 0 rows with 0 data columns
 1 id          I  U _id
 2 createddate I    _version_datetime
 3 createdby   I O  _version_user
 4 createdby   I O  _created_user
 5 deletedby   I    _deleted_by
 6 createddate I    _created
 7 serial      I  U _serial
__EMPTY_SHEET

### Sheet with default rows, but only one column

my $sheet2 = make_sheet columns => [ 'intgr' ];
ok defined $sheet2, 'Create sheet with one intgr column';

my $cols2 = $sheet2->layout->columns_search(exclude_internal => 1);
cmp_ok @$cols2, '==', 1, '... one column';
is $cols2->[0]->name_short, 'integer1', '... column = integer1';
cmp_ok $sheet2->content->row_count, '==', 2, '... two rows';

is $sheet2->content->row_by_serial(1)->current->cell('integer1'), 50, '... value first row';
is $sheet2->content->row_by_serial(2)->current->cell('integer1'), 99, '... value second row';

is $sheet2->debug(show_layout => 1, show_internal => 0, show_revid => 0,  show_rowid => 0),
    <<__SIMPLE_SHEET, '... debug sheet';
Sheet ${\$sheet2->id}=sheet 2, 2 rows with 1 data columns
 8 intgr         O  integer1
= 8  =
| 50 |
| 99 |
__SIMPLE_SHEET

### sheet with all currently supported columns

my $sheet3 = make_sheet rows => [],
   columns => [ qw/string intgr enum tree date daterange file person/ ];
ok defined $sheet3, 'Create sheet with most columns';
is $sheet3->debug(show_layout => 1, show_internal => 0, show_revid => 0, show_rowid => 0),
    <<__ALL_COLUMNS, '... debug sheet columns';
Sheet ${\$sheet3->id}=sheet 3, 0 rows with 8 data columns
 8 string        O  string1
 9 intgr         O  integer1
10 enum          O  enum1
    default ordering: position
      1   foo1
      2   foo2
      3   foo3
11 tree          O  tree1
       tree1
       tree2
           tree3
12 date          O  date1
13 daterange     O  daterange1
14 file          O  file1
15 person        O  person1
__ALL_COLUMNS

### sheet with all currently supported values
my $sheet4 = make_sheet;
ok defined $sheet4, 'Create sheet with all values';
is $sheet4->debug(show_layout => 0, show_internal => 0, show_revid => 0, show_rowid => 0),
   <<__ALL_VALUES, '... debug sheet values';
Sheet ${\$sheet4->id}=sheet 4, 2 rows with 8 data columns
= 8   = 9  = 10   = 11 = 12         = 13               = 14         = 15        =
| Foo | 50 | foo1 |    | 2014-10-10 | 2012-02-10 to 2⋮ | myfile.txt | Doe, John |
| Bar | 99 | foo2 |    | 2009-01-02 | 2008-05-04 to 2⋮ | myfile.txt | Doe, John |
__ALL_VALUES

done_testing;
