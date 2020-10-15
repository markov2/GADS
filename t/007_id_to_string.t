use Linkspace::Test;

my @data = (
  { string1    => 'Foo',
    integer1   => '100',
    enum1      => 7,
    tree1      => 10,
    date1      => '2010-10-10',
    daterange1 => ['2000-10-10', '2001-10-10'],
    curval1    => 1,
  },
  { string1    => 'Bar',
    integer1   => '200',
    enum1      => 8,
    tree1      => 11,
    date1      => '2011-10-10',
    daterange1 => ['2000-11-11', '2001-11-11'],
    curval1    => 2,
  },
);

my $curval_sheet = make_sheet;

my $sheet   = make_sheet
    rows           => \@data,
    curval_sheet   => $curval_sheet,
    curval_columns => [ 'string1', 'enum1' ],
);

my $user1 = make_user '1';

my @tests = (
    [ enum1   => 7,                 'foo1'        ]
    [ tree1   => 11,                'tree2'       ],
    [ person1 => $user1,            'User1, User1'],
    [ curval1 => $curval_sheet->id, 'Bar, foo2'   ],
    [ rag1    => 'b_red',           'Red'         ],
);

foreach my $test (@tests)
{   my ($field, $id, $string) = @$test;

    my $col = $layout->column($field);
    ok defined $col, "Test column $field";
    ok $col->has_fixedvals, '... has fixed values';
    is $col->id_as_string($id), $string, '... id string as expected';
    is $col->id_as_string(undef), '', '... undef id string as expected';
}

done_testing;
