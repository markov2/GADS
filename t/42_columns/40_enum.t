# Check the Integer column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});

ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/enum=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Enum', '...';

### Adding enums

my @some_enums = qw/tic tac toe/;
ok $sheet->layout->column_update($column1, { enumvals => \@some_enums }),
    'Insert some enums';
like logline, qr/add enum option \Q$_/, "... log creation of $_"
    for @some_enums;

my $retr_enums = $column1->enumvals;   # records!
cmp_ok @$retr_enums, '==', @some_enums, '... all were stored';
is $retr_enums->[0]->value, 'tic', '... expected 1';
is $retr_enums->[1]->value, 'tac', '... expected 2';
is $retr_enums->[2]->value, 'toe', '... expected 3';

is $column1->enumvals_string, 'tic, tac, toe', '... enumvals_string';

is $column1->id_as_string($retr_enums->[0]->id), 'tic', '... id to string 1';
is $column1->id_as_string($retr_enums->[1]->id), 'tac', '... id to string 2';
is $column1->id_as_string($retr_enums->[2]->id), 'toe', '... id to string 3';
ok !defined $column1->id_as_string(-1), '... id to string, non existing';

### low level instantiate to avoid the cache
my $column1d = Linkspace::Column->from_id($column1->id, sheet => $sheet);
isnt $column1d, $column1, 'recreated object';
ok defined $column1d, 'Reload via id, avoiding cache';
isa_ok $column1d, 'Linkspace::Column::Enum', '...';

#TODO: enums tac, toe, other   one delete, one create, other same id
#TODO: enum rename: the id is refers to a different name
#TODO: ->enumvals(include_deleted)   when Enum datun can be created
#TODO: ->enumvals(order => 'asc')
#TODO: ->enumvals(order => 'desc')
#TODO: ->enumvals(order => 'error')
#TODO: ->random
#TODO: ->_is_valid_value
#TODO: ->export_hash
#TODO: ->additional_pdf_export
#TODO: ->export_hash
#TODO: ->import_hash

done_testing;

