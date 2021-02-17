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

__PACKAGE__->db_accessors;

### 2020-05-25: columns in GADS::Schema::Result::Sort
# id         type       layout_id  order      parent_id  view_id

#XXX Legacy: should get rit of these in the DB

my @sort_types = (
  { name => 'asc',    description => 'Ascending'  },
  { name => 'desc',   description => 'Descending' },
  { name => 'random', description => 'Random'     },
);

my %sort_types = map +($_->{name} => $_->{description}), @sort_types;

#-----------------
=head1 METHODS: Constructors
=cut

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
