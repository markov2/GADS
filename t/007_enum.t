use Linkspace::Test;

foreach my $num_deleted (0..1)
{
    my $sheet   = make_sheet 1;
    my $layout  = $sheet->layout;

    my $enum = $columns->{enum1};
    if($num_deleted)
    {
        $enum->enumvals([
            { value => 'foo2', id    => 2 },
            { value => 'foo3', id    => 3 }
        ]);
        $enum->write;
    }

    my $record = GADS::Records->new(
        user    => $sheet->user,
        layout  => $layout,
        schema  => $schema,
    )->single;

    is($record->fields->{$enum->id}->as_string, "foo1", "Initial enum value correct");
    is(@{$record->fields->{$enum->id}->deleted_values}, $num_deleted, "Deleted values correct for record edit");

    $record = GADS::Record->new(
        user    => $sheet->user,
        layout  => $layout,
        schema  => $schema,
    );
    $record->initialise;
    is(@{$record->fields->{$enum->id}->deleted_values}, 0, "Deleted values always zero for new record");
}

done_testing;
