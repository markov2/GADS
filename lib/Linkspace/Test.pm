
package Linkspace::Test;

use warnings;
use strict;

use Log::Report    'linkspace';

require Test::More;
use Import::Into;
use Importer       ();

use Linkspace;

our @EXPORT = qw/logs logs_purge/;

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    Test::More->import::into($caller);
    warnings->import::into($caller);
    strict->import::into($caller);

    Importer->import_into(__PACKAGE__, $caller, @EXPORT);

    $::linkspace = Linkspace->start(
        log_dispatchers => [ +{   # We cannot start a CALLBACK from config
            type     => 'CALLBACK',
            callback => \&log,
            mode     => 'VERBOSE',
        } ],
    );
}

my @loglines;
sub log($$$$)
{   my ($cb, $options, $reason, $message) = @_;
    my $line = $cb->translate($options, $reason, $message);
    push @loglines, $line =~ s/\n\z//r;
}
sub logs { my @l = @loglines; @loglines = (); @l }
sub logs_purge() { @loglines = () }

# Call logs_purge before the end of your test-script to ignore this
END { warn "untested log: $_\n" for @loglines }

1;
