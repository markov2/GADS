use Test::More; # tests => 1;
use Log::Report;

my $user = test_user;
my %data = (
    string1    => 'Foobar',
    date1      => '2014-10-10',
    daterange1 => ['2000-10-10', '2001-10-10'],
    enum1      => 'foo1',
    tree1      => 'tree1',
    integer1   => 10,
    person1    => $user,
    curval1    => 1,
    file1 => {
        name     => 'file.txt',
        mimetype => 'text/plain',
        content  => 'Text file content',
    },
);

my %as_string = (
    string1    => 'Foobar',
    date1      => '2014-10-10',
    daterange1 => '2000-10-10 to 2001-10-10',
    enum1      => 'foo1',
    tree1      => 'tree1',
    integer1   => 10,
    person1    => $user1->fullname,
    curval1    => 'Foo',
    file1      => 'file.txt',
);

my $curval_sheet = make_sheet '2';

my $sheet   = make_sheet '1', rows => 2,
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1' ];

$sheet->content->row_create({})->revision_create(\%data);

my $row1 = $sheet->content->current->row(3);

foreach my $field (keys %as_string)
{   is $row1->cell($field)->as_string, $as_string{$field}, "... check $field";
}

# Tests to ensure correct curval values in record
foreach my $initial_fetch (0..1)
{
    my $row = $sheet->content->current->row(3,
        curcommon_all_fields => $initial_fetch,
    );

    my $datum  = $row->cell('curval1');
    my $values = $datum->field_values;
    cmp_ok @$values, '==', 1, '... initial curval fields';

#XXX ARRAY of HASH with 1 entry?
    my ($value) = values %{$values->[0]};
    is $value->as_string, "Foo", '... value of curval field';

    my $for_code = $datum->field_values_for_code(level => 1)->{1};
    cmp_ok keys %$for_code, '==', 7, '... initial curval fields';
}

done_testing;
