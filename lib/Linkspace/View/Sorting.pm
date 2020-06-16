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

package Linkspace::View::Sorting;

use Log::Report     'linkspace';

use Moo;
extends 'Linkspace::DB::Table';

use namespace::clean;

sub db_table { 'Sort' }

sub db_fields_unused { [ 'order' ] }

### 2020-05-25: columns in GADS::Schema::Result::Sort
# id         type       layout_id  order      parent_id  view_id

#XXX Legacy: should get rit of these in the DB

my %standard_fields = (
    -11 => '_id',
    -12 => '_version_datetime',
    -13 => '_version_user',
    -14 => '_deleted_by',
    -15 => '_created',
    -16 => '_serial',
);

my @sort_types = (
  { name => 'asc',    description => 'Ascending' },
  { name => 'desc',   description => 'Descending' },
  { name => 'random', description => 'Random' },
);
my %sort_types = map +($_->{name} => $_->{description}), @sort_types;

#-----------------
=head1 METHODS: Constructors
=cut

sub from_record($%)
{   my ($class, $record) = (shift, shift);

    #XXX Convert from legacy internal IDs. This can be removed at
    # some point.  XXX convert to database update script.

    my $col_id = $record->layout_id;
    if($col_id && $col_id < 0)
    {   my $new_col = $self->column($standard_fields{$col_id}) or panic;
        $record->update({ layout_id => $new_col->id });
        $record->layout_id($new_col);
    }

    $class->SUPER::from_record($record, @_);
}

sub _sort_create($%)
{   my ($self, $insert, %args) = @_;
    $sort_types{$insert->{type}}
        or error __x"Invalid sort type {type}", type => $insert->{type};

    $self->create($insert, %args);
}

#-----------------
=head1 METHODS: Accessors

=head2 \@h = $class->sort_types;
Returns and ARRAY of HASHes, each with a short code (name) and description
of a sorting rule.
=cut

sub sort_types { \@sort_types }


=head2 my $info = $sort->info;
Convert the sort into a HASH, which is used in C<view.tt>
=cut

sub info
{   my $self = shift;
    my $pid    = $self->parent_id;
    my $col_id = $self->column_id;

     +{ id        => $self->id,
        type      => $self->type,
        column_id => $col_id,
        parent_id => $pid 
        filter_id => $pid ? "${pid}_${col_id}" : $col_id,
      };
}



1;

