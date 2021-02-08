## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::File;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column';

# This column type uses three tables:
#
### 2020-09-03: columns in GADS::Schema::Result::FileOption
# id         filesize   layout_id
# --> configuration of the File column-type
#
### 2020-09-03: columns in GADS::Schema::Result::File
# id           value        child_unique layout_id    record_id
# --> the File datum connects (multiple) filevals to a column.
#     !!! file.value == fileval.id
#
### 2020-09-24: columns in GADS::Schema::Result::Fileval
# id             content        is_independent
# name           edit_user_id   mimetype
# --> the File content, is a separate table because they can be very
#     large and probably also reused.

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue  { 1 }
sub datum_class     { 'Linkspace::Datum::File' }
sub form_extras     { [ 'filesize' ], [] }
sub retrieve_fields { [ qw/name mimetype id/ ] }
sub sprefix         { 'value' }
sub string_storage  { 1 }
sub value_field     { 'name' }
sub tjoin           { +{ $_[0]->field_name => 'value' } }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(File       => { layout_id => $col_id});
    $::db->delete(FileOption => { layout_id => $col_id});
}

###
### Instance
###

has _fileoption => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $::db->get_record(FileOption => { layout_id => $_[0]->id }) },
);

sub max_file_size { $_[0]->_fileoption->{filesize} }

# Convert based on whether ID or name provided
sub value_field_as_index
{   my ($self, $value) = @_;
    !$value || $value =~ /^[0-9]+$/ ? 'id' : $self->value_field;
}

sub is_valid_value($)
{   my ($self, $value) = @_;

    (my $file_id) = $value =~ /^\s*([0-9]+)\s*$/
        or error __x"'{int}' is not a valid id of a file for '{col.name}'",
            int => $value, col => $self;

    $::db->get_record(Fileval => $file_id)
        or error __x"File {int} is not found for '{col.name}'",
            int => $value, col => $self;

    $file_id;
}

sub _column_extra_update($)
{   my ($self, $extra, %args) = @_;
    $self->SUPER::_column_extra_update($extra, %args);

    if(defined(my $filesize = $extra->{filesize}))
    {    my $data = { filesize => $filesize };
         my $reload_id;
         if(my $opt = $self->_fileoption)
         {   $opt->update($data);
             $reload_id = $opt->id;
         }
         else
         {   $data->{layout_id} = $self->id;
             my $result = $::db->create(FileOption => $data);
             $reload_id = $result->id;
         }
         $self->_fileoption($::db->get_record(FileOption => $reload_id));
    }
    $self;
}

sub resultset_for_values
{   my $self = shift;
    $::db->search(Fileval => {
        'files.layout_id' => $self->id,
    }, {
        join => 'files',
        group_by => 'me.name',
    });
}

sub export_hash
{   my $self = shift;
    my $h = $self->SUPER::export_hash(@_);
    $h->{filesize} = $self->max_file_size;
    $h;
}

1;

