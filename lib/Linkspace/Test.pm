
package Linkspace::Test;

use warnings;
use strict;

use Log::Report    'linkspace';

use Test::More;
use Import::Into;
use Importer       ();
use Data::Dumper   qw/Dumper/;

use Linkspace;

our @EXPORT = qw/
   logline logs logs_purge
   test_site
/;

our $guard;  # visible for guard test only

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    Test::More->import::into($caller);
    warnings->import::into($caller);
    strict->import::into($caller);

    $Data::Dumper::Indent   = 1;
    $Data::Dumper::Sortkeys = 1;
    Data::Dumper->import::into($caller, 'Dumper');

    Importer->import_into(__PACKAGE__, $caller, @EXPORT);

    $::linkspace = Linkspace->start(
        log_dispatchers => [ +{   # We cannot start a CALLBACK from config
            type     => 'CALLBACK',
            callback => \&log,
            mode     => 'VERBOSE',
        } ],
    );

    # All database changes get lost when the test script terminates.
    $guard = $::db->begin_work;
}

END { $guard->rollback if $guard }

### Logging

my @loglines;
sub log($$$$)
{   my ($cb, $options, $reason, $message) = @_;
    my $line = $cb->translate($options, $reason, $message);
    push @loglines, $line =~ s/\n\z//r;
}
sub logs { my @l = @loglines; @loglines = (); @l }
sub logline { @loglines ? shift @loglines : undef }
sub logs_purge() { @loglines = () }

# Call logs_purge before the end of your test-script to ignore this
END { warn "untested log: $_\n" for @loglines }


### Some objects

my ($site);

sub test_site()
{   return $site if $site;

    $site = Linkspace::Site->site_create({
        hostname => 'test-site.example.com',
    });

    is logline, "info: Site created ${\$site->id}: test-site",
        "created default site ${\$site->id}";

    $site;
}

1;
