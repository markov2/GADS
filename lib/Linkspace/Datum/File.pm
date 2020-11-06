## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

sub db_table { 'File' }

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;

    # Files should normally only be submitted by IDs. Allow submission by
    # hashref for tests etc
    my @file_ids = map +(ref $_ eq 'HASH' ? $class->_create_file($_) : $_),
        flat $values;

    [ sort { $a <=> $b } @file_ids ];
}

### 2020-11-06: columns in GADS::Schema::Result::File
# id           value        child_unique layout_id    record_id

sub _create_file($)
{   my ($thing, $insert) = @_;
    $::db->create(Fileval => $insert)->id;
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

