use strict;
use warnings;

package Linkspace::DBICProfiler;
use base 'DBIx::Class::Storage::Statistics';

use Log::Report 'linkspace';
use Time::HiRes  qw(time);

my $start;

sub print($) { trace $_[1] }

sub query_start(@)
{   my $self = shift;
    $self->SUPER::query_start(@_);
    $start   = time;
}

sub query_end(@)
{   my $self = shift;
    $self->SUPER::query_end(@_);
    trace __x"execution took {e%0.4f} seconds elapse", e => time-$start;
}

1;
