# Extracted from t/009_typeahead.t
# Test type-ahead for calc fields

use Linkspace::Test;
#   not_ready => 'Waiting for Calc';

my $sheet   = make_sheet columns => [ qw/daterange calc/ ];
warn $sheet->debug(all => 1);

my $column1 = $sheet->layout->column('calc1');
ok defined $column1, 'Fond calc column';

my $v1a     = $column1->values_beginning_with('2');
cmp_ok @$v1a, '==', 0,
     'Typeahead on calculated integer does not search as string begins with';

done_testing;
