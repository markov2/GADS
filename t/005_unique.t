
use Linkspace::Test;

my $user1 = make_user '2';

my $data = {
    string1    => 'Bar',
    integer1   => 99,
    date1      => '2009-01-02',
    enum1      => 1,
    tree1      => 4,
    daterange1 => ['2008-05-04', '2008-07-14'],
    person1    => $user1,
    file1 => {
        name     => 'file1.txt',
        mimetype => 'text/plain',
        content  => 'Text file1',
    },
};

my $sheet = make_sheet 1,
    rows      => [ $data ],
    calc_code => 'function evaluate (L1string1)
        return L1string1
    end',
    calc_return_type => 'string',
);
my $layout  = $sheet->layout;

my $columns = $layout->column_search(userinput => 1);
$layout->column_update($_ => { is_unique => 1 }) for @$columns;

my $row1    = $sheet->content->row_create;

my %rev;

foreach my $col ($layout->all(userinput => 1))
{
    try { $row1->revision_create({ $col => $data->{$col->name} }) };
    like $@, qr/must be unique but value .* already exists/,
        "Failed to write unique existing value for ".$col->name);

    $layout->column_update($col => { is_unique => 0 });
}

# Now calc unique values
{   $layout->column_update(calc1 => { is_unique => 1 });

    $row1->cell_update(calc1 => $data->{string1});
    like $@, qr/must be unique but value .* already exists/,
        "Failed to write unique existing value for calc value";

    $layout->column_update(calc1 => { is_unique => 0 });
}

# Calc with child unique
{
    $layout->column_update(calc1   => { is_unique => 1 });
    $layout->column_update(string1 => { can_child => 1 });

    # First a write that will fail, which is the string value that will cause
    # the calc value to be a duplicate. This will cause a unique error as the
    # string is field in the calc and therefore the calc needs to be unique

    my $row2 = $sheet->content->row_create({parent => $row1});
    my $rev = $row2->revision_create({string1 => $data->{string1});

    like $@, qr/must be unique but value .* already exists/,
        "Failed to write unique existing value for calc-dependent value";

    # Now make string value not a child value, which will mean that the even
    # though the child calc value is the same, it will be accepted as it is
    # copied from the parent.
    #
    # Make date field the child field instead

    $layout->column_update(date1 => { can_child => 1 });
    $layout->column_update(string1 => { can_child => 0 });

    # Restart child record (row3)

    my $row3 = $sheet->content->row_create({ parent => $row1 });
    $row3->cell_update({ date1 => '2013-10-10' });

    is $row3->cell('calc1'), $data->{string1}, "Duplicated child calc written";
}

done_testing;
