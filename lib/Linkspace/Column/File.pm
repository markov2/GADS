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
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column';

###
### META
###

INIT { __PACKAGE__->register_type }

sub can_multivalue  { 1 }
sub retrieve_fields { [ qw/name mimetype id/ ] }
sub form_extras     { [ 'filesize' ], [] }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(File       => { layout_id => $col_id});
    $::db->delete(FileOption => { layout_id => $col_id});
}

###
### Instance
###

sub sprefix { 'value' }
sub tjoin   { +{ $_[0]->field => 'value' } }
sub string_storage { 1 }

# Convert based on whether ID or name provided
sub value_field_as_index
{   my ($self, $value) = @_;
    !$value || $value =~ /^[0-9]+$/ ? 'id' : $self->value_field
}

has filesize => (
    is      => 'rw',
    isa     => Maybe[Int],
);

after build_values => sub {
    my ($self, $original) = @_;

    $self->value_field('name');
    if(my $file_option = $original->{file_options}->[0])
    {   $self->filesize($file_option->{filesize});
    }
};

sub _is_valid_value($)
{   my ($self, $value) = @_;
    (my $file_id) = $value =~ /^\s*([0-9]+)\s*$/
        or error __x"'{int}' is not a valid id of a file for '{col}'",
            int => $value, col => $self->name;

    $::db->get_record(Fileval => $file_id))
        or error __x"File {int} is not found for '{col}'",
            int => $value, col => $self->name;

    $file_id;
}

sub _collect_form_extra
{   my ($class, $params) = @_;
    my $extra = $class->SUPER::_collect_form_extra($params);
    $extra->{filesize} = $params->{filesize};
    $extra;
}

sub write_special
{   my ($self, %options) = @_;
    my $id   = $options{id};
    my %data = (filesize => $self->filesize);
    
    if(my $file_option = $::db->get_record(FileOption => { layout_id => $id }))
    {   $file_option->update(\%data);
    }
    else
    {   $data{layout_id} = $id;
        $::db->create(FileOption => \%data);
    }

    return ();
};

sub resultset_for_values
{   my $self = shift;
    $::db->search(Fileval => {
        'files.layout_id' => $self->id,
    }, {
        join => 'files',
        group_by => 'me.name',
    });
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    my $old_size = $self->filesize;
    my $new_size = $value->{filesize};

    notice __x"Update: filesize from {old} to {new}", old => $old_size, new => $new_size
        if $report && ($old_size // -1) != ($new_size // -1);

    $self->filesize($new_size);
};

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_, filesize => $self->filesize);
}

1;

