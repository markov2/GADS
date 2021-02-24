# part 4 of t/007_code.t
# Set of tests to check multi-value calc returns

{
    # This calc code will return an array with the number of elements being the
    # value of integer1; or, if integer1 is 10 or 11, an array with 2 elements
    # one way round or the other. If the order of array elements changes, then
    # the string value may change but the "changed" status should be false.
    # This is so that when returning a calc based on another multi-value, it
    # doesn't matter if the order of the input changes.
    my $sheet   = make_sheet
        data      => [],
        calc_code => "
            function evaluate (L1integer1)
                a = {}
                if L1integer1 < 10 then
                    for i=1, L1integer1 do
                        a[i] = 10
                    end
                elseif L1integer1 == 10 then
                    return {100, 200}
                else
                    return {200, 100}
                end
                return a
            end
        ",
        calc_return_type => 'string';

    my $int     = $layout->column('integer1');

    $layout->column_update(calc1 => { is_multivalue => 1 });

    my $row = $layout->row_create;

    # First test number of elements being returned and written
    # One element returned
    $row->revision_create({integer1 => 1});

    my $rset = $schema->resultset('Calcval');
    cmp_ok $rset->count, '==', 1, "Correct number of calc values written to database";

    my $datum = $row->cell($calc);
    is $datum->as_string, "10", "Correct multivalue calc value, one element";

    # Now return 2 elements
    is($rset->count, 1, "Second calc value not yet written to database");
    $row->revision_create({integer1 => 2});
    $datum->re_evaluate;

    is($datum->as_string, "10, 10", "Correct multivalue calc value for 2 elements");
    $datum->write_value;

    is($rset->count, 2, "Second calc value written to database");

    # Test changed status of datum. Should only update after change and
    # re-evaluation.  Reset record and reload
    $record->clear;

    $record = $sheet->content->row(1);
    $datum = $record->cell($calc);

    # Third element
    $row->revision_create({integer1 => 3});

    # Not changed to begin with
    ok ! $datum->changed, "Calc value not changed";

    # Now should change
    $datum->re_evaluate;
    ok $datum->changed, "Calc value changed after re-evaluation");
    is($rset->count, 2, "Correct number of database values before write");
    $datum->write_value;
    is($rset->count, 3, "Correct number of database values after write");

    # Set back to one element, check other database values are removed
    $record->cell_update($int => 1);
    $datum->re_evaluate;
    $datum->write_value;

    is($rset->count, 1, "Old calc values deleted from database");

    # Set to value for next set of tests
    $record->cell_update($int => 10, no_alerts => 1);
    is($rset->search({ record_id => 2 })->count, 2, "Correct number of database calc values");

    # Next test that switching array return values does not set changed status
    $record = $layout->row(1);
    $datum = $record->cell($calc);
    $record->cell_update($int => 10);
    $datum->re_evaluate;

    # Not changed from initial write
    ok ! $datum->changed, 0, "Calc value not changed after writing same value";
    is $datum->as_string, "100, 200", "Correct multivalue calc value for int value 10";

    # Switch the return elements
    $record->cell_update($int => 11);
    $datum->re_evaluate;

    ok ! $datum->changed, 0, "Calc datum not changed after switching return elements";
    is $datum->as_string, "200, 100", "Correct multivalue calc value after switching return";

    $datum->write_value;
    is($rset->search({ record_id => 2 })->count, 2, "Correct database values after switch");
}

done_testing;
