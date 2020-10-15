# Rewrite from t/010_delete.t

use Linkspace::Test
   not_ready => 'needs basic rows';

set_fixed_time '10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S';

my $sheet   = make_sheet;
my $content = $sheet->content;

### Check quick search matches

my $results1 = $content->search('foo1');
ok defined $results1, 'Quick search for first record count';
cmp_ok $results1->count, '==', 1, '... counted 1';
cmp_ok @{$results1->rows}, '==', 1, '... 1 row';

cmp_ok $content->row_count, '==', 2, 'Initial records created';

my $row1 = $content->first_row;
ok $content->row_delete($row1), 'Delete one row from sheet';
cmp_ok $content->row_count, '==', 1, '... sheet now fewer rows';
my $rev1 = $row1->current;

### Check that record cannot be found via quick search

my $results2 = $content->search('foo1');
ok defined $results2, 'Quick search for, now record deleted';
cmp_ok $results2->count, '==', 0, '... found none';
cmp_ok @{$results2->rows}, '==', 0, '... no row';

### Find deleted record via current ID

my $row1b = try { $content->row($row1->current_id) };  # throws warning
ok ! defined $row1b, 'Deleted rows are usually ignored';

my $row1c = $content->row($row1->current_id, include_deleted => 1);
ok defined $row1c, 'Deleted rows available on explicit request';

is $row1c->deleted_by, test_user, '... recorded actuator';
is $row1c->deleted_when, '2014-10-10T01:00:00', '... recorded moment';

### Find deleted record via historical record ID

my $row1d = Linkspace::Row->from_revision_id($rev1->id, content => $content);
ok defined $row1b, 'Got deleted row via revision-id';
ok $row1d->is_deleted, '... row still deleted ;-)';

### Find deleted record via all records

my $all_rows = $content->rows(include_deleted => 1);
my $first = $all_rows->[0];
is $first->current_id, $row1->current_id, '... found in rows including deleted';

done_testing;
