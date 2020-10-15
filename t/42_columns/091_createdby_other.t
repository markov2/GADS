# rewrite of t/010_createdby.t

use Linkspace::Test
    not_ready => 'waiting for sheet, simple';

my $sheet   = make_sheet
    rows =>    [{ string1 => 'foobar1' }],
    columns => [ 'string1' ];

my $user    = make_user 4;
$::session->switch_user($user);

cmp_ok $sheet->content->nr_rows, '==', 1, 'Initial row created';

### Update record as different user

my $row1a = $sheet->content->search->row(1);
$row1a->cell_update( { string1 => 'foobar2' });

my $row1b = $sheet->content->search->row(1);  # reload from db
isnt $row1a, $row1b, 'Reload row from db';
is $row1a->current_id, $row1b->current_id, '... but about same row';

my $rev = $row1b->current;
is $rev->cell('_createdby'), 'User4, User4', 'Revision has correct version editor';

is $rev->cell('_created_user'), 'User1, User1',
    'Record retrieved as group has correct createdby';

is $row1b->created_by, 'User1, User1', '... from row';

done_testing;
