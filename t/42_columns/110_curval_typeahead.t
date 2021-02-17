# Test type-ahead for curval fields
# Extracted from t/009_typeahead.t

use Linkspace::Test
    not_ready => "Waiting for test_sheet";

my $curval_sheet = make_sheet rows => 2;

my $sheet = make_sheet rows => [
  { curval1    => $curval_sheet->row_at(2),
    daterange1 => ['2012-02-10', '2013-06-15'],
  },
  { curval1    => $curval_sheet->row_at(1),
    daterange1 => ['2012-02-10', '2013-06-15'],
  },
];

my $layout  = $sheet->layout;

# A curval typeahead often has many thousands of values. It should therefore
# not return any values if calling the values function (e.g. in the edit page)
# otherwise it may hang for a long time

ok 1, 'Curval typeahead without search';

my $column2 = $layout->column('curval1');
$layout->column_update($column2 => { value_selector => 'typeahead' });

cmp_ok @{$column2->all_values}, '==', 0, "... no values";
cmp_ok @{$column2->filtered_values}, '==', 0, "... no filtered values";

my $values2a = $column2->values_beginning_with('bar');
cmp_ok @$values2a, '==', 1, "... search beginning 'bar' found one";
my $value2a0 = $values2a->[0];
is ref $value2a0, 'HASH', "Typeahead returns hashref for curval";
is $value2a0->{id}, 2, "Typeahead result has correct ID";
is $value2a0->{name}, "Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008",
   "Typeahead returned correct values";

my $values2c = $column2->values_beginning_with('');
cmp_ok @$values2c, '==', 2, "... searching for blank finds all";

#### Add a filter to the curval

my $column3 = $column2;
$layout->column_update($column3 => { filter => { rule => {
    column => 'integer1', operator => 'equal', value => '50',
}}});

my $values3a = $column3->values_beginning_with('50');
cmp_ok @$values3a, '==', 1, "Typeahead returned correct number of results (with matching filter)";

my $values3b = $column3->values_beginning_with('99');
cmp_ok @$values3b, '==', 0, "Typeahead returned correct number of results (with no match filter)";

#### Add a filter which has record sub-values in. This should be ignored.

my $column4 = $column3;
$layout->column_update($column4 => { filter => { rule => {
    column => 'string1', operator => 'equal', value => '$L1string1',
}}});

my $values4a = $column4->values_beginning_with('50');
cmp_ok @$values4a, '==', 1, "Typeahead returned correct number of results (with matching filter)";

my $values4b = $column4->values_beginning_with('99');
cmp_ok @$values4b, '==', 1, "Typeahead returned correct number of results (with no match filter)";

done_testing;
