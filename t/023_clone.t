
use Linkspace::Test;

my $curval_sheet = make_sheet 2;

my $data = [ {
    integer1   => 150,
    string1    => 'Foobar',
    curval1    => 1,
    date1      => '2010-01-01',
    daterange1 => ['2011-02-02', '2012-02-02'],
    enum1      => 'foo1',
    tree1      => 'tree1',
} ];

my $sheet   = make_sheet 1,
    rows             => $data,
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1'],
);

my $layout  = $sheet->layout;
my $columns = $sheet->columns;
my $content = $sheet->content;

$curval_sheet->add_autocur(
    refers_to_sheet   => $sheet,
    related_column    => 'curval1',
    curval_columns    => [ 'string1' ],
    curval_sheet      => $sheet,
);

my @colnames = keys %{$data->[0]};
my $curval = $layout->column('curval1');
my $string = $layout->column('string1');

my $row1 = $content->row(3, curcommon_all_fields => 1);
is $row1->cell('string1')->as_string, "Foobar", "String correct to begin with";
is $row1->cell($curval)->as_string, 'Foo', "Curval correct to begin with";
my $ids = join '', @{$row1->cell($curval)->ids};

# Standard clone first
for my $reload (0..1)
{   my $row2 = $content->row(3, curcommon_all_fields => 1);
    my $cloned2 = $row2->clone;

    my %vals = map +($_->id => $cloned2->cell($_)->html_form),
        @{$layout->columns(@colnames)};

    if($reload)
    {   $cloned2 = $content->row_create(\%vals);
    }

    my $cloned2b = $content->row($cloned2->current_id);

    foreach my $colname (@colnames)
    {   my $cell = $cloned2b->cell($colname);
        if($colname eq 'curval1')
        {   is $cell->as_string, "Foo", "$colname correct after cloning";
            my $ids_new = join '', @{$cell->ids};
            is $ids_new, $ids, "ID of newly written field same";
        }
        elsif ($colname eq 'daterange1')
        {   is $cell->as_string, '2011-02-02 to 2012-02-02', "$colname correct after cloning";
        }
        else
        {   is $cell->as_string, $data->[0]{$colname}, "$colname correct after cloning";
        }
    }
}

# Set up curval to be allow adding and removal
$layout->column_update($curval, { show_add => 1, value_selector => 'noshow' });

# Clone the record and write with no updates
my $cloned3 = $row1->clone;
my $row3    = $content->row($cloned3->current_id);   # reload

is $row3->cell('string1')->as_string, "Foobar", "String correct after cloning";
is $row3->cell($curval)->as_string, "Foo", "Curval correct after cloning";
my $ids_new = join '', @{$cloned->cell($curval)->ids};
isnt $ids, $ids_new, "ID of newly written field different";

# Clone the record and update with no changes (as for HTML form submission)
for my $reload (0..1)
{   my $row4 = $content->row(3, curcommon_all_fields => 1);
    my $cloned4 = $row4->clone;
    my $curval_datum = $cloned4->cell($curval);

    my @vals = map $_->{as_query}, @{$curval_datum->html_form};
    ok "@vals", "HTML form has record as query";
    cmp_ok @vals, '==', 1, "One record in form value";

    if ($reload) # Start writing to virgin record, as per new record submission
    {   $cloned4 = $content->row_create({ string1 => 'Foobar' });
        $curval_datum = $cloned4->cell($curval);
    }
    $content->cell_update($curval_datum => \@vals);

    my $cloned4b = $content->row($cloned4->id);
    is $cloned4b->cell('string1')->as_string, "Foobar", "String correct after cloning";
    is $cloned4b->cell($curval)->as_string, "Foo", "Curval correct after cloning";

    $ids_new = join '', @{$cloned4b->cell($curval)->ids};
    isnt $ids, $ids_new, "ID of newly written field different";
}

# Clone the record and update with changes (as for HTML form submission edit)
foreach my $reload (0..1)
{   my $row5 = $content->row(3, curcommon_all_fields => 1);
    my $cloned5 = $row5->clone;
    my $curval_datum = $cloned5->cell($curval);
    my @vals = map $_->{as_query}, @{$curval_datum->html_form};
    s/Foo/Foo2/ foreach @vals;

    if($reload)
    {   $cloned5 = $content->row_create({ string1 => 'Foobar' });
        $curval_datum = $cloned5->cell($curval);
    }
    $cloned5->cell_update($curval_datum => \@vals);

    my $cloned5b = $content->row($cloned5->current_id);
    is $cloned5b->cell($string)->as_string, "Foobar", "String correct after cloning";
    is $cloned5b->cell($curval)->as_string, "Foo2", "Curval correct after cloning";

    $ids_new = join '', @{$cloned5b->cell($curval)->ids};
    isnt $ids, $ids_new, "ID of newly written field different";
}

done_testing;
