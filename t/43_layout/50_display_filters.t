# Check the Linkspace::Filter::Display
#
# The display_filter may have a purpose restricted to Curval, but it is
# generally available anyway.
#
# This script only checks some basic functionality: the next will contain
# many more combinations and tricks.

use Linkspace::Test;
use Linkspace::Util qw(to_id);

my @all_strings = qw/tic tac toe and more/;
my $sheet = make_sheet columns => [ 'intgr', 'string' ],
   rows => [ map +{ string1 => $_ }, @all_strings ];

my $layout  = $sheet->layout;
my $monitor = $layout->column('integer1');
my $string  = $layout->column('string1');
my $rows    = $sheet->content->rows;

my $dummy   = $monitor->display_filter;
ok defined $dummy, 'Dummy display_filter present';
ok ! $dummy->is_active, '... but not active';

# No rules with yourself in it
try { $layout->column_update($monitor, { display_filter =>
  [ { monitor => $monitor, operator => 'equal', value => 'aap' } ]
}) };

is $@->wasFatal->message, 'Display filter rules cannot include column itself',
  'No recursive monitoring';

sub check_filter($$$$$)
{   my ($condition, $rules, $expected, $summary, $descr) = @_;
    ok 1, "Construct filter $descr";
    
    $layout->column_update($monitor => {
        display_filter    => $rules,
        display_condition => $condition,
    });

    like logline, qr/changed fields: display_condition/, '... logged';

    my $df = $monitor->display_filter;
    ok defined $df, '... constructed';

    is $df->is_active, scalar @$rules, '... counted rules';
    is $df->as_text."\n", $summary, '... looks good';

    my @matches = map $_->current->cell($string), grep $df->do_show($_), @$rows;
    is "@matches", $expected, "... values as expected";

    my @h = map +{ id => to_id($_->{monitor}), operator => $_->{operator},
       value => $_->{value} }, @$rules;

    is_deeply $df->as_hash, { condition => $condition || 'AND', rules => \@h },
         '... to hash';
}

check_filter undef, [ ], "@all_strings", "\n", 'No display filter';

check_filter AND => [ { monitor => $string, operator => 'equal', value => 'tac' } ],
    'tac', <<__SUMMARY, 'Equal one';
Displayed when the following is true: ${\$string->name} equal tac
__SUMMARY

check_filter OR => [ { monitor => $string, operator => 'contains', value => 'a' } ],
   'tac and', <<__SUMMARY, 'Match two';
Displayed when the following is true: ${\$string->name} contains a
__SUMMARY

check_filter OR => [
    { monitor => $string, operator => 'equal', value => 'tac' },
    { monitor => $string, operator => 'equal', value => 'more' },
  ], 'tac more', <<__SUMMARY, 'Equal OR two';
Displayed when any of the following are true: ${\$string->name} equal tac; ${\$string->name} equal more
__SUMMARY

check_filter AND => [
    { monitor => $string, operator => 'equal', value => 'tac' },
    { monitor => $string, operator => 'equal', value => 'more' },
  ], '', <<__SUMMARY, 'Equal AND two: no answers';
Displayed when all the following are true: ${\$string->name} equal tac; ${\$string->name} equal more
__SUMMARY

done_testing;
