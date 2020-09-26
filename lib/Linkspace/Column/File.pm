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
sub form_extras     { [ 'filesize' ], [] }
sub retrieve_fields { [ qw/name mimetype id/ ] }
sub sprefix         { 'value' }
sub string_storage  { 1 }
sub value_field     { 'name' }

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

sub tjoin   { +{ $_[0]->field => 'value' } }

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

sub _is_valid_value($)
{   my ($self, $value) = @_;

    (my $file_id) = $value =~ /^\s*([0-9]+)\s*$/
        or error __x"'{int}' is not a valid id of a file for '{col}'",
            int => $value, col => $self->name;

    $::db->get_record(Fileval => $file_id)
        or error __x"File {int} is not found for '{col}'",
            int => $value, col => $self->name;

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

