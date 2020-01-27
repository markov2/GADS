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

sub can_multivalue  { 1 }
sub retrieve_fields { [ qw/name mimetype id/ ] }

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    $::db->delete(File       => { layout_id => $col_id});
    $::db->delete(FileOption => { layout_id => $col_id});
}

###
### Instance
###

sub sprefix { 'value' }
sub tjoin   { +{ $_[0]->field => 'value' } }

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

    $self->string_storage(1);
    $self->value_field('name');
    my ($file_option) = $original->{file_options}->[0];
    if ($file_option)
    {
        $self->filesize($file_option->{filesize});
    }
};

sub validate
{   my ($self, $value, %options) = @_;
    return 1 if !$value;

    if($value !~ /^[0-9]+$/ || ! $::db->get_record(Fileval => $value))
    {
        return 0 unless $options{fatal};
        error __x"'{int}' is not a valid file ID for '{col}'",
            int => $value, col => $self->name;
    }

    1;
}

# Any value is valid for a search, as it can include begins_with etc
sub validate_search {1};

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
    notice __x"Update: filesize from {old} to {new}", old => $self->filesize, new => $values->{filesize}
        if $report && (
            (defined $self->filesize xor defined $values->{filesize})
            || (defined $self->filesize && defined $values->{filesize} && $self->filesize != $values->{filesize})
        );
    $self->filesize($values->{filesize});
};

sub export_hash
{   my $self = shift;
    my $hash = $self->SUPER::export_hash;
    $hash->{filesize} = $self->filesize;
    $hash;
}

1;

