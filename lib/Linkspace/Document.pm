=pod
GADS
Copyright (C) 2015 Ctrl O Ltd

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

package Linkspace::Document;
use Moo ();

use Log::Report  'linkspace';
use Scalar::Util qw(blessed);
use List::Util   qw(first);

use Linkspace::Sheet ();
use MooX::Types::MooseLike::Base qw/ArrayRef HashRef/;

=head1 NAME
Linkspace::Document - manages sheets for one site

=head1 SYNOPSIS

  my $doc     = $::session->site->document;
  my $all_ref = $doc->all_sheets;

=head1 DESCRIPTION

=head1 METHODS: Constructors
M

=head2 my $doc = Linkspace::Document->new(%options);
Required is C<site>.
=cut

has site => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

#-------------------------
=head1 METHODS: Sheet management

=head2 my @all = $doc->all_sheets;
Return all sheets, even those which the session user is not allowed to access.
They are sorted by name (case insensitive).
=cut

has all_sheets => (
   is      => 'lazy',
   isa     => ArrayRef,
   builder => sub
   {   my $self   = shift;
       my @sheets = map Linkspace::Sheet->from_record($_,
           document => $self,
       ), $::db->resultset('Instance')->all;

       $self->_sheet_indexes_update($_) for @sheets;
       [ sort { fc($a->name) cmp fc($b->name) } @sheets ];
   }
}


=head2 my $sheet = $doc->sheet($which);
Get a single sheet, C<$which> may be specified as name, short name or id.
=cut

sub _sheet_indexes_update($;$)
{   my ($self, $sheet) = (shift, shift);
    my $to = @_ ? shift : $sheet;

    my $index = $self->_sheet_index;
    $index->{$sheet->id}         =
    $index->{'table'.$sheet->id} =
    $index->{$sheet->name}       =
    $index->{$sheet->short_name} = $to;
}

has _sheet_index => (
    is      => 'lazy',
    isa     => HashRef,
    builder => sub
    {   my $self  = shift;
        my $index = {};
        _sheet_index_update $index, $_, $_ for @{$self->all_sheets};
        $index;
    }
);

sub sheet($)
{   my ($self, $which) = @_;
    $which or return;

    return $which
        if blessed $which && $which->isa('Linkspace::Sheet');

    $self->_sheet_index->{$which};
}


=head2 $doc->sheet_delete($which);
Remove the indicated sheet.
=cut

sub sheet_delete($)
{   my ($self, $which) = @_;

    my $sheet = $self->sheet($which)
        or return;

    $self->_sheet_indexes_update($sheet => undef);
    $sheet->delete;

    $self->site->structure_changed;
    $self;
}

=head2 my $new_sheet = $doc->sheet_update($which, %changes);
When a sheet gets updated, it may need result in a new sheet (which may
be the same as the old sheet).
=cut

sub sheet_update($%)
{   my ($self, $which, %changes) = @_;

    my $sheet = $self->sheet($which) or return;
    $changes && keys %$changes or return $sheet;

    $self->_sheet_indexes_update($sheet => undef);
    $sheet->sheet_update(%changes);

    my $new = $doc->sheet($sheet->id);
    $self->_sheet_indexes_update($new);

    $new;
}

=head2 my $sheet = $doc->sheet_create(%insert);
=cut

sub sheet_create(%)
{   my ($self, %insert) = @_;
    my $report_only = delete $insert{report_only};
    my $sheet       = Linkspace::Sheet->sheet_create(%insert);

    $self->_sheet_indexes_update($sheet);
    $self->sheet($sheet->id);
}

=head2 my $sheet = $doc->first_homepage
Returns the first sheet which has text in the 'homepage_text' field, or
the first sheet when there is none.
=cut

sub first_homepage
{   my $all = shift->all_sheets;
    my $has = first { $_->homepage_text } @$all;
    $has || $all->[0];
}

#----------------------
=head1 METHODS: Set of columns

In the original design, column knowledge was limited to single sheets: when
you were viewing one sheet (with a certain layout), you could only access
those columns.  However: cross sheet references are sometimes required.
=cut

# We do often need many of the columns, so get the info for all of them
# (within the site) at once.  Probably less than 100.
has _column_index => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $doc_cols = Linkspace::Sheet::Layout->load_columns($self);
        +{ map +($_->id => $_), @doc_cols }
    },
);

=head2 my $column = $doc->column($id);
=cut

sub column($)
{   my ($self, $id) = @_;
    my $column = $self->_column_index->{$id};
    $column->isa('Linkspace::Column')   # upgrade does not change pointer
        or Linkspace::Column->from_record($column, document => $self);
    $column;
}

=head2 \@columns = $doc->columns(@ids);

=head2 \@columns = $doc->columns(\@ids);
=cut

sub columns
{   my $self  = shift;
    [ map $self->column($_), ref $_[0] eq 'ARRAY' ? @{$_[0]} : @_ ];
}

=head2 \@cols = $doc->columns_for_sheet($sheet);

=head2 \@cols = $doc->columns_for_sheet($sheet_id);
=cut

sub columns_for_sheet($)
{   my ($self, $which) = @_;
    my $sheet_id = blessed $sheet ? $which->id : $which;
    $self->columns(grep $_->instance_id == $sheet_id, @{$self->_column_index});
}

=head2 \@cols = $doc->columns_with_filters;
=cut

sub columns_with_filters()
{   my $self = shift;
    $self->columns(grep $_->filter ne '{}' && $_->filter ne ''} @{$self->_column_index});
}

#---------------
=head1 METHODS: Files
Manage table "Fileval", which contains uploaded files.  Files many not
be connected to sheets (be independent), related to a person and/or
relate to a sheet cell.

=head2 my \@files = $doc->independent_files;
=cut

sub independent_files($;$)
{   my ($self, $search, $attrs) = @_;
    [ $::db->search(Fileval => { is_independent => 1 }, { order_by => 'me.id' })->all ];
}

=head2 my $file_set = $doc->file_set($id);
=cut

sub file_set($)
{   my ($self, $set_id) = @_;
    $::db->get_record(Fileval => $set_id);
}

=head2 $doc->file_create(%insert);
=cut

sub file_create(%)
{   my ($self, %insert) = @_;
    $insert{edit_user_id} = $insert{is_independent} ? undef : $::session->user->id;
    $::db->create(Fileval => \%insert);
}

#---------------
=head1 METHODS: Pointers
Manage table "Current", which contains pointers to records.
=cut

sub columns_refering_to($)
{   my ($self, $dest) = @_;
    my @ref_ids = $::db->search(CurvalField => { child_id => $dest->id })
        ->get_column('id')->all;
    $self->columns(@ref_ids);
}

sub columns_link_child_of($)
{   my ($self, $parent) = @_;
    my $pid   = $parent->id;
    my $index = $self->_column_index;
    my @childs = grep { ($_->link_parent || 0) == $pid } values %$index;
    $self->columns(@childs);
}

#--------------
=head1 METHODS: Find rows
Rows (records) are referenced by many different id's.

=head2 my $row = $doc->row($kind, $id, %options);
Option C<rewind> says XXX.
=cut

sub row($$%)
{   my ($self, $kind, $id, %args) = @_;
    $id or return;

    if(my $sheet = $args{sheet}) ...
    #XXX see old GADS::Record->find...
      'pointer_id'
      'record_id'
      'deleted_currentid'
      'deleted_recordid'
      'current_id';
}

#--------------
=head1 METHODS: Find Other

=head2 $doc->column_unuse($column);
Remove a column wherever it is used.
=cut

sub column_unuse($)
{   my ($self, $column) = @_;

    $_->filter_remove_column($column)
       for @{$self->columns_with_filters};

    $_->column_unuse($column)
       for @{$self->all_sheets};

}

1;
