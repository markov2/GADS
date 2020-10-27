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

use warnings;
use strict;

package Linkspace::Datum::File;

use Log::Report 'linkspace';
use Linkspace::Util  qw(flat);

use Moo;
extends 'Linkspace::Datum';

### 2020-09-03: columns in GADS::Schema::Result::Fileval
# id             content        is_independent
# name           edit_user_id   mimetype

sub _create_file($)
{   my ($thing, $insert) = @_;
    $::db->create(Fileval => $insert)->id;
}

sub _unpack_values($%)
{   my ($class, $cell, $values, %args) = @_;

    # Files should normally only be submitted by IDs. Allow submission by
    # hashref for tests etc
    my @file_ids = map +(ref $_ eq 'HASH' ? $class->_create_file($_) : $_),
        flat $values;

    [ sort { $a <=> $b } @file_ids ];
}

sub file_id { $_[0]->value }
sub file    { $::db->get_record(Fileval => { id => $_[0]->value }) }
sub file_meta  # content is expensive
{   $::db->get_record(Fileval => { id => $_[0]->value },
        { columns => [ qw/id name mimetype/ ] });
}

sub content    { $_[0]->file->content }
sub as_string  { $_[0]->file_meta->{name} }

sub presentation($$)
{   my ($self, $cell, $show) = @_;
    push @{$show->{files}}, $self->file_meta;
}

1;

