# Rewrite of t/007_curval_perms.t
use Linkspace::Test
    not_ready => 'Waiting for curval';

#XXX override should work differently: a temporary flag on the $user

my $curval_sheet = make_sheet
     user_permission_override => 0,
     columns   => [ qw/string integer date daterange enum/ ],
     rows      => [
  {  string1    => 'Foo',
     integer1   => 50,
     date1      => '2014-10-10',
     daterange1 => ['2012-02-10', '2013-06-15'],
     enum1      => 1,
  },
];

my $sheet   = make_sheet
    rows                     => [ { string1 => 'Foo', curval1 => 1 } ],
    columns                  => [ qw/string curval/ ],
    multivalues              => 1,
    curval_sheet             => $curval_sheet,
    curval_columns           => [ 'string1', 'integer1' ],
    user_permission_override => 0,
);
my $content = $sheet->content;

# Permissions to all curval fields
my $results1 = $content->search(
    user   => $sheet->user_normal1,   ### switch user?
);

is $results1->row(1)->cell('curval1'), 'Foo, 50', 'Curval correct with full perms';

# user   => $sheet->user_normal1,
my $row1 = $content->row(2);
is $row1->cell('curval1'), 'Foo, 50', 'Curval correct with full perms';

### Now remove permission from one of the curval sub-fields

$curval_sheet->layout->column_update(integer1 => { permissions => {} });

# Permissions to all curval fields
my $results2 = $content->search(
    user   => $sheet->user_normal1,   ### switch user?
);

is $results2->row(1)->cell('curval1'), 'Foo', 'Curval correct with limited perms';

### Now check that user_permission_override on layout works

$layout->user_permission_override(1);

my $result3  = $content->search->row(1); 
is $result3->cell('curval1'), 'Foo, 50', 'Curval correct with full perms';

my $row3     = $content->row(2);
is $row3->cell('curval1'), 'Foo, 50', 'Curval correct with full perms';

### Now with override permission on a column

$layout->column('curval1')->override_permission(1);

my $results4 = $content->search->row(1);
is $result4->cell('curval1'), 'Foo, 50', 'Curval correct with override';

my $row4     = $content->row(2);
is $row4->cell('curval1'), 'Foo, 50', 'Curval correct with override';

done_testing;
