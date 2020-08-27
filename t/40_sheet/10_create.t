#!/usr/bin/env perl
# Test the creation, update and destruction of sheets (avoiding columns and
# other administrative groups)

use Linkspace::Test;

use_ok 'Linkspace::Sheet';

my $site = test_site;

my $doc  = $site->document;
ok defined $doc, 'Open document set';
isa_ok $doc, 'Linkspace::Site::Document', '...'; 
is $doc->site, $site, '... refers to site';

is_deeply $doc->all_sheets, [], 'No sheets yet';

### Create first sheet (there also is the default sheet of the app)

my $sheet1 = $doc->sheet_create({
    name => 'first sheet',
    name_short => 'first',
});
ok defined $sheet1, 'Create my first sheet, id='.$sheet1->id;
my $sheet1_id = $sheet->id;

my $path = $site->path . '/first';
isa_ok $sheet1, 'Linkspace::Sheet', '...';
is logline, "info: Instance created $sheet1_id: $path", '... log';

is $sheet1->site, $site, '... refers to site';
is $sheet1->document, $doc, '... refers to document';

is $sheet1->name, 'first sheet', '... check name';
is $sheet1->name_short, 'first', '... check name_short';
is $sheet1->identifier, 'first', '... check identifier';
is $sheet1->path, $path, '... check path';

### Reloading of first
my $sheet1a = $site->sheet('first');
is $sheet1a, $sheet1, '... address sheet via cache by sort name';

my $sheet1b = $site->sheet('first sheet');
is $sheet1b, $sheet1, '... address sheet via cache by long name';

my $sheet1c = $site->sheet($sheet1_id);
is $sheet1c, $sheet1, '... address sheet via cache by id';

my $sheet1d = $site->sheet('table'.$sheet1_id);
is $sheet1d, $sheet1, '... address sheet via cache by table label';

my $sheet1e = Linkspace::Sheet->from_id($sheet1_id, document => $doc);
ok defined $sheet1e, 'Reloaded first via database';
isnt $sheet1e, $sheet1, '... is new object';
is $sheet1e->id, $sheet1_id, '... correct sheet';
is $sheet1e->site_id, $sheet1->site_id, '... correct site';

### Check loading of childs

foreach my $helper ( qw/layout access/ )
{   my $pkg    = "Linkspace::Sheet::\u$helper";
    my $handle = $sheet1->$helper;
    ok defined $handle, "Loaded $helper";
    isa_ok $handle, $pkg, '...';
    is $handle->sheet, $sheet1, '... refers back to sheet';
}

diag 'Many more components to follow';

### Sheet delete

$doc->sheet_delete($sheet1);
ok !defined $doc->sheet($sheet1_id), 'Deleted first sheet';
ok !defined $site->sheet($sheet1_id), '... missing via site';
is logline, "info: Instance $sheet1_id='$path' deleted", 'logged';

ok !Linkspace::Sheet->from_id($sheet1_id, document => $doc), '... removed from DB';

done_testing;
