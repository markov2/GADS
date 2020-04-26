
package Linkspace::Test;

require Test::More;
use Import::Into;

sub import(%)
{   my ($class, %args) = @_;

    my $caller = caller;
    Test::More->import::into($caller);
    warnings->import::into($caller);
    strict->import::into($caller);

    return if exists $args{connect_db} ? $args{connect_db} : 1;

#XXX connect to the database
}

1;
