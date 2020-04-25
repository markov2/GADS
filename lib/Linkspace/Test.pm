
package Linkspace::Test;

require Test::More;
use Import::Into;

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    Test::More->import::into($caller);
}

1;
