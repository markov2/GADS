# Extracted from t/009_typeahead.t
# Test type-ahead for calc fields

use Linkspace::Test
    not_ready => 'Waiting for Calc';

my $sheet   = empty_sheet;
my $layout  = $sheet->layout;

my $column1 = $layout->column('calc1');

my $v1a     = $column1->values_beginning_with('2');
cmp_ok @$v1a, '==', 0,
     'Typeahead on calculated integer does not search as string begins with';

done_testing;
