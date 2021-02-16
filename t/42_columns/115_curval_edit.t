
use Linkspace::Test
    not_ready => 'rewrite ongoing';

foreach my $delete_not_used (0..1)
{
    my $curval_sheet  = empty_sheet;
    my $curval_layout = $curval_sheet->layout;

    my $sheet   = make_sheet
        curval_colums    => $curval_sheet->column('string1'),
        calc_return_type => 'string',
        calc_code        => qq{function evaluate (L1curval1)
            if L1curval1 == nil then
                return ""
            end
            ret = ""
            for _, curval in ipairs(L1curval1) do
                ret = ret .. curval.field_values.L2string1
            end
            return ret
        end};

    my $layout  = $sheet->layout;

    # Add autocur and calc of autocur to curval sheet, to check that gets
    # updated on main sheet write
    my $autocur = $curval_sheet->layout->column_create({
        type            => 'autocur',
        related_column  => $sheet->column('curval1'),
        curval_column   => $sheet->column('string1'),
    });

    $curval_sheet->layout->column_update(calc1 => { code => <<'__CODE' });
        function evaluate (L2autocur1)
            return_value = ''
            for _, v in pairs(L2autocur1) do
                return_value = return_value .. v.field_values.L1integer1
            end
            return return_value
        end
__CODE


    # Set up curval to be allow adding and removal
    $layout->column_update(curval1 => {
        delete_not_used => $delete_not_used,
        show_add        => 1,
        value_selector  => 'noshow',
    });

    my $row = $sheet->content->row(3);

#XXX now it gets hairy
#   my $calcmain = $columns->{calc1};

    my $curval_datum = $row->cell('curval1');
    is $curval_datum, '', "Curval blank to begin with";

    # Add a value to the curval on write
    my $curval_count = $curval_sheet->nr_rows;

    my $curval_string = $curval_layout->column('string1');
    $row->cell_update(curval1 => [ $curval_string->field_name."=foo1"] );

    is $row->cell('calc1'), "foo1", "Main calc correct";
    my $curval_count2 = $curval_sheet->nr_rows;
    is $curval_count2, $curval_count + 1, "New curval record created";

    my $record = $sheet->content->row(3);
    is $record->cell('calc1'), "foo1", "Main calc correct after load";

    $curval_datum = $record->cell('curval1');
    is $curval_datum, 'foo1', "Curval value contains new record";
    my $curval_record_id = $curval_datum->ids->[0];

    # Check full curval field that has been written
    my $curval_record = $curval_sheet->content->row($curval_record_id);
    is $curval_record->cell('calc1'), 50, "Calc from autocur of curval correct";

    # Add a new value, keep existing
    $curval_count = $curval_sheet->nr_rows;
    $record->cell_update(curval1 => [ $curval_string->field_name."=foo2", $curval_record_id ]);

    is $record->cell('calc1'), "foo1foo2", "Main calc correct";

    $curval_count2 = $curval_sheet->nr_rows;
    is $curval_count2, $curval_count + 1, "Second curval record created";

    my $record1b = $sheet->content->row(3);
    isnt $record1b, $record, 'Reload produces different object';

    is $record1b->cell('calc1'), "foo1foo2", "Main calc correct";
    $curval_datum = $record->cell('curval1');
    like $curval_datum, qr/^(foo1; foo2|foo2; foo1)$/, "Curval value contains second new record";

    # Check autocur from added curval
    my $row3 = $sheet->content->row(6);
    is $row3->cell('calc1'), "50", "Autocur calc correct";

    # Edit existing
    my $row4 = $sheet->content->row(3);
    $curval_datum = $row4->cell('curval1');
    $curval_count = $sheet->content->nr_rows;
    my ($d) = map $_->{id}, grep { $_->{field_values}->{L2string1} eq 'foo2' }
        @{$curval_datum->for_code};
    $row->cell_update(curval1 => [$curval_string->field_name."=foo5&current_id=$d", $curval_record_id]);
    $curval_count2 = $sheet->content->nr_rows;
    is $curval_count2, $curval_count, "No new curvals created";
#XXXX

    $record->find_current_id(3);
    is($record->cell('calc1'), "foo1foo5", "Main calc correct");
    $curval_datum = $record->fields->{$curval->id};
    like($curval_datum->as_string, qr/^(foo1; foo5|foo5; foo1)$/, "Curval value contains updated record");

    # Edit existing - one edited via query but no changes, other changed as normal
    $curval_count = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    my ($d1) = map $_->{id}, grep { $_->{field_values}->{L2string1} eq 'foo1' }
        @{$curval_datum->for_code};
    my ($d2) = map $_->{id}, grep { $_->{field_values}->{L2string1} eq 'foo5' }
        @{$curval_datum->for_code};
    $curval_datum->set_value([$curval_string->field."=foo1&current_id=$d1", $curval_string->field."=foo6&current_id=$d2"]);
    $record->write(no_alerts => 1);
    $curval_count2 = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    is($curval_count2, $curval_count, "No new curvals created");
    $record->clear;
    $record->find_current_id(3);
    is $record->cell('calc1'), "foo1foo6", "Main calc correct";

    $curval_datum = $record->fields->{$curval->id};
    like($curval_datum->as_string, qr/^(foo1; foo6|foo6; foo1)$/, "Curval value contains updated and unchanged records");

    # Edit existing - no actual change
    $record = $sheet->content->row(3);
    $curval_datum = $record->fields->{$curval->id};
    $curval_count = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    $curval_datum->set_value([
        # Construct a query equivalent to what it would be if a user edited a
        # curval edit field and then saved it without any changes. That is, the
        # query string of the form, plus the current_id parameter
        map {
            $_->{record}->as_query . "&current_id=" . $_->{record}->current_id
        } @{$curval_datum->values}
    ]);
    # Set other value to ensure main record is flagged as changed and full write happens
    $record->fields->{$columns->{date1}->id}->set_value('2020-10-10');
    $record->write(no_alerts => 1);
    $curval_count2 = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    is($curval_count2, $curval_count, "No new curvals created");
    $record->clear;
    $record->find_current_id(3);
    is($record->fields->{$calcmain->id}->as_string, "foo1foo6", "Main calc correct");
    $curval_datum = $record->fields->{$curval->id};
    like($curval_datum->as_string, qr/^(foo1; foo6|foo6; foo1)$/, "Curval value still contains same values");

    # Delete existing
    $curval_count = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    $curval_datum->set_value([$curval_record_id]);
    $record->write(no_alerts => 1);
    $curval_count2 = $schema->resultset('Current')->search({ instance_id => 2 })->count;
    is($curval_count2, $curval_count, "Curval record not removed from table");
    $curval_count2 = $schema->resultset('Current')->search({ instance_id => 2, deleted => undef })->count;
    is($curval_count2, $curval_count - $delete_not_used, "Curval record removed from live records");
    $curval_count2 = $schema->resultset('Current')->search({ instance_id => 2, deleted => { '!=' => undef } })->count;
    is($curval_count2, $delete_not_used, "Correct number of deleted records in curval sheet");
    $record->clear;
    $record->find_current_id(3);
    is($record->fields->{$calcmain->id}->as_string, "foo1", "Main calc correct");
    $curval_datum = $record->fields->{$curval->id};
    is($curval_datum->as_string, 'foo1', "Curval value has lost value");

    # Save draft
    $record = GADS::Record->new(
        user   => $sheet->user_normal1,
        layout => $layout,
        schema => $schema,
        curcommon_all_fields => 1,
    );
    $record->initialise(instance_id => $layout->instance_id);
    $curval_datum = $record->fields->{$curval->id};
    $curval_datum->set_value([$curval_string->field."=foo10", $curval_string->field."=foo20"]);
    $record->fields->{$columns->{integer1}->id}->set_value(10); # Prevent calc warnings
    $record->write(draft => 1);
    $record->clear;
    $record->load_remembered_values(instance_id => $layout->instance_id);
    $curval_datum = $record->fields->{$curval->id};
    $curval_record_id = $curval_datum->ids->[0];
    my @form_values = @{$curval_datum->html_form};
    my @qs = ("field8=foo10&field9=&field10=&field15=", "field8=foo20&field9=&field10=&field15=");
    foreach my $form_value (@form_values)
    {
        # Draft record, so draft curval edits should not have an ID as they
        # will be submitted afresh
        ok(!$form_value->{id}, "Draft curval edit does not have an ID");
        is($form_value->{as_query}, shift @qs, "Valid query data for draft curval edit");
    }
    @form_values = map { $_->{as_query} =~ s/foo20/foo30/; $_->{as_query} } @form_values;
    $curval_datum->set_value([@form_values]);
    $record->write(no_alerts => 1);
    my $current_id = $record->current_id;
    $record->clear;
    $record->find_current_id($current_id);
    $curval_datum = $record->fields->{$curval->id};
    is($curval_datum->as_string, 'foo10; foo30', "Curval value contains new record");

    # Check that autocur calc field is correct before main record write
    $record->clear;
    $record->find_current_id(3);
    $curval_datum = $record->fields->{$curval->id};
    $curval_datum->set_value([$curval_string->field."=foo10"]);
    $curval_record = $curval_datum->values->[0]->{record};
    is($curval_record->fields->{$curval_string->id}->as_string, 'foo10', "Curval value contains correct string value");
    is($curval_record->fields->{$calc->id}->as_string, '50', "Curval value contains correct autocur before write");
    is($curval_record->fields->{$autocur->id}->as_string, 'Foo', "Autocur value is correct");
}

done_testing;
