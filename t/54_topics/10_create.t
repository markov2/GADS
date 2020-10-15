
use Linkspace::Test
    not_ready => 'waiting for Topics';

my $sheet   = make_sheet;
my $layout  = $sheet->layout;
my $content = $sheet->content;

# Create 2 topics. One will be some initial summary fields. The other will
# contain an authorisation field. It will only be possible to edit the
# authorisation field once the summary is completed.

my $topic1 = $sheet->topic_create({ name => 'Summary' });
ok defined $topic1, 'Create tow topics';
isa_ok $topic1, 'Linkspace::Topic', '...';

my $topic2 = $sheet->topic_create({ name => 'Authorisation' });
isa_ok $topic2, 'Linkspace::Topic', '...';
cmp_ok @{$sheet->topics}, '==', 2, '... two topics created';

$layout->column_update(string1  => { topic => $topic1 });
$layout->column_update(integer1 => { topic => $topic1 });
$layout->column_update(date1    => { topic => $topic1 });
$layout->column_update(enum1    => { topic => $topic2 });

#XXX there was a bug which did not set the topic on $date

# Check correct number of topics against fields
cmp_ok $::db->search(Layout => { topic_id => { '!=' => undef }})->count, '==', 4,
    'Topics added to fields';

# Set up editing restriction
$sheet->topic_update($topic1 => { prevent_edit_topic => $topic2 });

#XXX test missing

done_testing;
