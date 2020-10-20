# Rewrite t/006_invalid_values.t

use Linkspace::Test
    not_ready => 'needs rewrite';

#XXX use Datum objects directly

my $sheet = make_sheet rows => [
    {
        string1    => 'foobar',
        integer1   => '',
        enum1      => '',
        tree1      => '',
        date1      => '',
        daterange1 => ['', ''],
    }
];
my $layout = $sheet->layout;

my $results = $sheet->content->search;
cmp_ok $results->count, '==', 1, "One record in test dataset";

my $row = $results->row(1);

my $string1 = $columns->{'string1'};
$string1->force_regex('[0-9]+');
# Try unchanged - should only result in warning
try { $record->fields->{$string1->id}->set_value("foobar") } hide => 'ALL';
ok(!$@, "No exception writing unchanged bad string value for force_regex settings" );

my ($warning) = $@->exceptions;
like($warning, qr/Invalid value/, "Correct warning writing unchanged bad string value for force_regex settings" );
# Error with normal changed
try { $record->fields->{$string1->id}->set_value("foo") };
like($@, qr/Invalid value/, "Failed to write bad string value for force_regex settings" );

my $integer1 = $columns->{'integer1'};
try { $record->fields->{$integer1->id}->set_value("bar") };
ok( $@, "Failed to write non-integer value" );

my $date1 = $columns->{'date1'};
try { $record->fields->{$date1->id}->set_value("20-10-10") };
ok( $@, "Failed to write invalid date" );

my $daterange1 = $columns->{'daterange1'};
try { $record->fields->{$daterange1->id}->set_value(["2010-10-10",""]) };
ok( $@, "Failed to write daterange with missing date" );

try { $record->fields->{$daterange1->id}->set_value(["2015-10-10","2011-10-10"]) };
ok( $@, "Failed to write daterange with dates in wrong order" );

try { $record->fields->{$daterange1->id}->set_value(["20-10-10","2011-10-10"]) };
ok( $@, "Failed to write daterange with invalid date" );

my $enum1 = $columns->{'enum1'};
try { $record->fields->{$enum1->id}->set_value(999) };
like( $@, qr/is not a valid enum/, "Failed to write invalid enum" );

my $tree1 = $columns->{'tree1'};
try { $record->fields->{$tree1->id}->set_value(999) };
like( $@, qr/not a valid tree node/, "Failed to write invalid tree" );

done_testing();
