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

### 2020-11-06: columns in GADS::Schema::Result::File
# id           value        child_unique layout_id    record_id

### 2020-09-03: columns in GADS::Schema::Result::Fileval
# id             content        is_independent
# name           edit_user_id   mimetype
my @cheap_fields = qw/id name edit_user_id is_independent mimetype/;

sub db_table { 'File' }

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;

    # Files should normally only be submitted by IDs. Allow submission by
    # hashref for tests etc
    my @file_ids = map +(ref $_ eq 'HASH' ? $class->_create_file($_) : $_),
        flat $values;

    [ sort { $a <=> $b } @file_ids ];
}

sub _create_file($)
{   my ($thing, $insert) = @_;
    $::db->create(Fileval => $insert)->id;
}

=head2 METHODS: Accessors
=cut

sub file_id        { $_[0]->value }
sub name           { $_[0]->file_meta->name }
sub is_independent { $_[0]->file_meta->is_independent }
sub edit_user_id   { $_[0]->file_meta->edit_user_id }
sub mimetype       { $_[0]->file_meta->mimetype }
sub content        { $_[0]->file->content }

sub edit_user
{   my $user_id = $_[1] or return;
    $::session->site->users->user($user_id);
}

# This one is not cached, because it may contain a huge content.
# Returned is a database object, which does not easy can be translated to the
# object for file_meta.  So for efficiency, either use file_meta() or file(),
# not both.

sub file { $::db->get_record(Fileval => { id => $_[0]->value }) }

sub file_meta  # content is expensive
{   $_[0]->{LDF_meta} ||=
        $::db->search(Fileval => { id => $_[0]->value }, { column => \@cheap_fields })->next;
}

sub presentation($$)
{   my ($self, $cell, $show) = @_;
    push @{$show->{files}}, $self->file_meta;
}

1;

