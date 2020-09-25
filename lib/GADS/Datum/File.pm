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

package GADS::Datum::File;

use Log::Report 'linkspace';
use Linkspace::Util  qw(flat);

use Moo;
use namespace::clean;

extends 'GADS::Datum';
with 'GADS::Role::Presentation::Datum::File';

### 2020-09-03: columns in GADS::Schema::Result::Fileval
# id             content        is_independent
# name           edit_user_id   mimetype

after set_value => sub {
    my ($self, $value) = @_;
    my $clone = $self->clone; # Copy before changing text

    my @in = sort(flat $value);

    my @values;
    foreach my $val (@in)
    {
        # Files should normally only be submitted by IDs. Allow submission by
        # hashref for tests etc
        if(ref $val eq 'HASH')
        {   my $file = $::db->create(Fileval => {
                name     => $val->{name},
                mimetype => $val->{mimetype},
                content  => $val->{content},
            });
            push @values, $file->id;
        }
        else
        {   push @values, $val;
        }
    }

    my @old    = sort @{$self->ids};
    my $changed = "@values" ne "@old";

    if($changed)
    {   my $column = $self->column;
        $column->is_valid_value($_, fatal => 1) for @values;

        # Simple test to see if the same file has been uploaded. Only works for
        # single files.
        if(@values == 1 && @old == 1)
        {   my $old_content = $::db->get_record(Fileval => $old[0])->content;
            $changed = 0 if $::db->search(Fileval => {
                id      => $values[0],
                content => $old_content,
            })->count;
        }
    }
    if($changed)
    {   $self->clear_files;
        $self->clear_init_value;
    }
    $self->changed($changed);
    $self->oldvalue($clone);
    $self->has_ids(1);
    $self->ids(\@values);
};

sub ids      { [ map $_->{id}, @{$_[0]->files} ] }
sub is_blank { ! @{$_[0]->ids} }

has has_ids => (
    is  => 'rw',
    isa => Bool,
);

sub value {
    my $self = shift;
    return [ map $_->{name}, @{$self->files} ] if $self->column->is_multivalue;
    my $s = $self->as_string;
    length $s ? $s : undef;
}

sub _build_files
{   my $self = shift;

    $self->has_init_value
       or return [ $self->_ids_to_files($self->ids) ];

    my @values = map { ref $_ eq 'HASH' && exists $_->{record_id} ? $_->{value} : $_ } @init_value;

    my @return = map {
          ref $_ eq 'HASH'
        ? +{ id => $_->{id}, name => $_->{name}, mimetype => $_->{mimetype} }
        : $self->_ids_to_files($_)
    } @values;

    $self->has_ids(1) if @values || $self->init_no_value;
    \@return;
}

sub _ids_to_files
{   my ($self, $ids) = @_;
    my @ids = ref $ids eq 'ARRAY' ? @$ids : $ids;
    @ids or return [];

    my $files_rs = $::db->search(Fileval => { id => \@ids },
       { columns => [qw/id name mimetype/] }
    );

    map +{ id => $_->id, name => $_->name, mimetype => $_->mimetype }, $files_rs->all;
}

sub search_values_unique { [ map $_->{name}, @{$_[0]->files} ] }

has content => (
    is      => 'lazy',
    builder => sub { $_[0]->_rset && $_[0]->_rset->content },
);

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->($self,
        ids   => $self->ids,
        files => $self->files,
        @_,
    );
};


sub as_string  { join ', ', map $_->{name}, @{$self->files || []} }
sub as_integer { panic "Not implemented" }
sub html_form  { $_[0]->ids }

1;

