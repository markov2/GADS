## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Createdby;

use Log::Report     'linkspace';
use List::Util      qw/uniq/;
use Linkspace::Util qw/index_by_id/;

use Moo;
extends 'Linkspace::Column::Person';

###
### META
###

__PACKAGE__->register_type;

sub is_optional      { 1 }    # Legacy
sub is_internal_type { 1 }
sub is_userinput     { 0 }
sub sprefix()        { 'createdby' }
sub tjoin            { 'createdby' }

###
### Class
###

sub _remove_column($) {}

###
### Instance
###


# Different to normal function, this will fetch users when passed a list of IDs
sub fetch_multivalues
{   my ($self, $victim_ids) = @_;
    $victim_ids && @$victim_ids or return +{ };

    my $users = $self->site->users;
    index_by_id [ map $users->user($_), uniq @$victim_ids ];
}

1;
