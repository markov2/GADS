#!/usr/bin/env perl

use Test::More; # tests => 1;
use strict;
use warnings;

use Linkspace::Filter;
use JSON qw(decode_json encode_json);
use Log::Report;
#use Data::Dumper;

my $rule1 = +{
   id       => 1,
   type     => 'string',
   value    => 'string1',
   operator => 'equal',
};

my $as_hash1 = {
    rules     => [ $rule1 ],
    condition => 'AND',
};

my $filter1 = Linkspace::Filter->from_hash($as_hash1);
ok defined $filter1, 'Created first filter';
isa_ok $filter1, 'Linkspace::Filter';
is_deeply $filter1->as_hash, $as_hash1, "construct as HASH1";

my $filter2 = Linkspace::Filter->from_json(encode_json $as_hash1);
is_deeply $filter2->as_hash, $as_hash1, "construct as JSON from HASH1";
ok defined $filter2, 'Created second filter';
isa_ok $filter2, 'Linkspace::Filter';

my $rules1 = $filter1->filters;
cmp_ok @$rules1, '==', 1, "found 1 filter";
is_deeply $rules1->[0], $rule1, "found rule";

is "@{$filter1->column_ids}", "1", "column_ids()";

# Now set different data
my $as_hash3 = {
    rules => [
        {
            id       => 2,
            type     => 'string',
            value    => 'string2',
            operator => 'equal',
        }
    ],
    condition => 'OR',
};

my $filter3 = Linkspace::Filter->from_json(encode_json $as_hash3);
is_deeply $filter3->as_hash, $as_hash3, "Created filter on HASH3";

is "@{$filter3->column_ids}", "2", "Column IDs of filter correct";

done_testing();
