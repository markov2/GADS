## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Permission;
use Moo;

use overload '""'  => 'long', fallback => 1;

has short => ( is => 'rw');

my %short2long = (
    read             => 'Values can be read',
    write_new        => 'Values can be written to new records',
    write_existing   => 'Modifications can be made to existing records',
    approve_new      => 'New records can be approved',
    approve_existing => 'Modifications to existing records can be approved',
    write_new_no_approval => 'Values for new records do not require approval',
    write_existing_no_approval => 'Modifications to existing records do not require approval',
);

my %short2medium = (
    read                       => 'Read',
    write_new                  => 'Write new',
    write_existing             => 'Edit',
    approve_new                => 'Approve new',
    approve_existing           => 'Approve existing',
    write_new_no_approval      => 'Write without approval',
    write_existing_no_approval => 'Edit without approval',
);

sub long       { $short2long{$_[1]}   || '' }
sub medium     { $short2medium{$_[1]} || '' }
sub all_shorts { [ sort keys %short2long ] }

1;
