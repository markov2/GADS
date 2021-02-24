# part 3 from t/007_code.t
use Linkspace::Test;

# Ensure that blank and null string fields in the database are treated the same
foreach my $test (qw/string_empty string_null calc_empty calc_null/)
{
    my $sheet   = make_sheet
        rows             => [ { string1 => '' } ],
        calc_code        => 'function evaluate (_id) return "" end',
        calc_return_type => 'string',
    );
    my $layout  = $sheet->layout;

    my $field = $test =~ /string/ ? 'L1string1' : 'L1calc1';
    my $code = "
        function evaluate ($field)
            if L1string1 == nil then
                return \"nil\"
            end
            if L1string1 == \"\" then
                return \"empty\"
            end
            return \"unexpected: \" .. L1string1
        end";

    my $calc2 = $layout->column_create({
       type      => 'calc',
        name   => 'L1calc2',
        code   => $code,
        permissions => $colperms,
    });

    # Manually update database to ensure that both stored empty strings and
    # undefined values are tested
    $schema->resultset('Calcval')->update({
        value_text => $test =~ /null/ ? undef : '',
    });
    $schema->resultset('String')->update({
        value => $test =~ /null/ ? undef : '',
    });

    # Force update of calc2 field
    $calc2->update_cached;

    my $row = $sheet->content->row(1);
    is $row->cell('calc2'), 'nil', "Calc from string correct ($test)";
}

done_testing;
