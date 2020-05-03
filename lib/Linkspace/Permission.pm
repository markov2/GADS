=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package Linkspace::Permission;
use Moo;

use overload '""'  => 'long', fallback => 1;

has short => ( is => 'rw');

my %short2long = (
    read             => 'Values can be read',
    write_new        => 'Values can be written to new records',
    write_existing   => 'Modifications can be made to existing records',
    approve_new      => 'Values for new records can be approved',
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
