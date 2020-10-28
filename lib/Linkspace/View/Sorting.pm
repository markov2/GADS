## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

