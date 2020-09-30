# Rewrite from t/015_string_zero.t

use Linkspace::Test
    not_ready => 'waiting for sheet';

my $sheet_nr = 0;

# Test for zero vs empty string in string
foreach my $value ('', '0')
{
    my $sheet   = make_sheet $sheet_nr,
        data      => [],
        calc_code => "function evaluate (L1integer1)\nreturn L1integer1\nend";

    my $layout  = $sheet->layout;

    my $row = $sheet->content->row_create;
    my $rev = $row->revision_create({
        string1 => $value,
        integer1 => $value,
    });

    if($value eq '0')
    {   ok ! $rev->cell($_)->is_blank, "... 0 is not blank for $_"
            for qw/string1 integer1 calc1/;
    }
    else
    {   ok   $rev->cell($_)->is_blank, "... '' is blank for $_"
            for qw/string1 integer1 calc1/;
    }

    ### Check filters

    foreach my $column (qw/string1 integer1 calc1/)
    {   next if $column->name_short eq 'integer1' && $value eq '';

        my $rules = { rules => {
            column   => $column,
            type     => 'string',
            operator => 'equal',
            value    => $value,
        }};

        my $view = $sheet->views->view_create({
            name        => 'Zero view',
            filter      => $rules,
            columns     => [ $column ],
        });

        my $results = $sheet->content->search(view => $view);
        cmp_ok $results->count, '==', 1,
            "One zero record for value '$value' col ID $col_id";
    }
}

done_testing;
