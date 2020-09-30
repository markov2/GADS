# Test type-ahead for enum fields
# Extracted from t/009_typeahead.t

use Linkspace::Test
    not_ready => 'Waiting for filled test_sheet';

my $sheet   = test_sheet rows => 3;
my $layout  = $sheet->layout;

my $column1 = $layout->column('enum1');

my $v1a = $column1->values_beginning_with('foo');
cmp_ok @$v1a, '==', 3, "Search for 'foo'";
is "@$v1a", "foo1 foo2 foo3", "... correct values";

my $v1b = $column1->values_beginning_with('foo1');
cmp_ok @$v1b, '==', 1, "Search for 'foo1'";
is "@$v1b", "foo1", "... correct values";

my $v1c = $column1->values_beginning_with('');
cmp_ok @$v1c, '==', 3, "All results for blank string";

done_testing;
