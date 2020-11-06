# Test the creation of test sheets

use Linkspace::Test;

### Empty sheet

my $sheet1 = make_sheet rows => [], columns => [];
ok defined $sheet1, 'Create empty test sheet';

cmp_ok @{$sheet1->layout->columns_search(exclude_internal => 1)}, '==', 0, '... no columns';
cmp_ok $sheet1->content->row_count, '==', 0, '... no rows';


### Sheet with default rows, but only one column

my $sheet2 = make_sheet columns => [ 'intgr' ];
ok defined $sheet2, 'Create sheet with one column';

my $cols2 = $sheet2->layout->columns_search(exclude_internal => 1);
cmp_ok @$cols2, '==', 1, '... one column';
is $cols2->[0]->name_short, 'integer1', '... column = integer1';
cmp_ok $sheet2->content->row_count, '==', 2, '... two rows';

done_testing;
