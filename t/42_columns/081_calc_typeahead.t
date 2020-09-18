# Test type-ahead for calc fields
# Extracted from t/009_typeahead.t

use Linkspace::Test;

plan skip_all => 'Waiting for filled test_sheet';

my $sheet   = test_sheet rows => 3;
my $layout  = $sheet->layout;

my $column1 = $layout->column('calc1');

my $v1a = $column1->values_beginning_with('2');
cmp_ok @$v1a, '==', 0, "Typeahead on calculated integer does not search as string begins with";

done_testing;
