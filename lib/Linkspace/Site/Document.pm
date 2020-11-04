## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Site::Document;

use Log::Report  'linkspace';
use Scalar::Util     qw(blessed);
use List::Util       qw(first);

use Linkspace::Util  qw(index_by_id);
use Linkspace::Sheet ();
use Moo;

=head1 NAME

Linkspace::Site::Document - manages sheets for one site

=head1 SYNOPSIS

  my $doc     = $::session->site->document;
  my $all_ref = $doc->all_sheets;

=head1 DESCRIPTION

=head1 METHODS: Constructors

=head2 my $doc = Linkspace::Site::Document->new(%options);
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

has _sheets_by_id => (
    is      => 'lazy',
    builder => sub
    {   my $self   = shift;
        my $sheets = Linkspace::Sheet->search_objects({site => $self->site},
            document => $self,
        );
        index_by_id @$sheets;
    }
);

has _sheets_by_name => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub
    {   my $by_id = shift->_sheets_by_id;
         +{ map +('table'.$_->id => $_, $_->name => $_, $_->name_short => $_),              values %$by_id };
    },
);

sub all_sheets
{   my $index = shift->_sheets_by_id;
    [ sort { fc($a->name) cmp fc($b->name) } grep defined, values %$index ];
}

=head2 my $sheet = $doc->sheet($which, $to?, $index?);
Get a single sheet, C<$which> may be specified as name, short name or id.
When C<$to> is undef, the sheet gets removed.
=cut

sub _sheet_indexes_update($;@)
{   my ($self, $sheet) = (shift, shift);
    my $to = @_ ? shift : $sheet;
    $self->_sheets_by_id->{$sheet->id} = $to;

    my $index = $self->_sheets_by_name;
    $index->{'table'.$sheet->id} =
    $index->{$sheet->name}       =
    $index->{$sheet->name_short} = $to;
    $sheet;
}


sub sheet($)
{   my ($self, $which) = @_;
    $which or return;

    return $which
        if blessed $which && $which->isa('Linkspace::Sheet');

    my $index = $which =~ /\D/ ? $self->_sheets_by_name : $self->_sheets_by_id;
    $index->{$which};
}


=head2 $doc->sheet_delete($which);
Remove the indicated sheet.
=cut

sub sheet_delete($)
{   my ($self, $which) = @_;

    my $sheet = $self->sheet($which)
        or return;

    $self->_sheet_indexes_update($sheet => undef);
    $sheet->_sheet_delete;
    $self;
}

=head2 $doc->sheet_update($which, %changes);
When a sheet gets updated.
=cut

sub sheet_update($$%)
{   my ($self, $which, $update, %args) = @_;
    my $sheet = $self->sheet($which) or return;
	keys %$update or return $sheet;

    $self->_sheet_indexes_update($sheet => undef);
    $sheet->_sheet_update($update);

    my $fresh = Linkspace::Sheet->from_id($sheet->id, document => $self, %args);
    $self->_sheet_indexes_update($fresh);
    $fresh;
}

=head2 my $sheet = $doc->sheet_create(\%insert, %options);
=cut

sub sheet_create($%)
{   my ($self, $insert, %args) = @_;
    my $class  = $args{class} || 'Linkspace::Sheet';
    my $sheet  = $class->_sheet_create($insert, document => $self, %args);
    $self->_sheet_indexes_update($sheet);
    $sheet;
}

=head2 my $sheet = $doc->first_homepage
Returns the first sheet which has text in the 'homepage_text' field, or
the first sheet when there is none.
=cut

sub first_homepage
{   my $sheets = shift->all_sheets;
    my $has    = first { $_->homepage_text } @$sheets;
    $has || $sheets->[0];
}

#----------------------
=head1 METHODS: Set of columns

In the original design, column knowledge was limited to single sheets: when
you were viewing one sheet (with a certain layout), you could only access
those columns.  However: cross sheet references are sometimes required.
=cut

# We do often need many of the columns, so get the info for all of them
# (within the site) at once.  Probably less than 100.
has _column_index_by_id => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $cols = Linkspace::Sheet::Layout->load_columns($self->site);
        $::db->schema->setup_record_column_finder($cols);
        index_by_id $cols;
    },
);

has _column_index_by_short => (
    is      => 'lazy',
    builder => sub {
        my $id_index = $_[0]->_column_index_by_id;
        +{ map +($_->name_short => $_), values %$id_index };
    },
);

=head2 \@columns = $doc->all_columns;
=cut

sub all_columns { [ values %{$_[0]->_column_index_by_id} ] }

=head2 my $column = $doc->column($which, %options);
Find a column by short_name or id, over all sheets.  When different sheets
define the same name, you get any.  You can check to have a certain user
access C<permission> in one go.
=cut

sub column($%)
{   my ($self, $which, %args) = @_;

    my $column = blessed $which ? $which
       : $self->_column_index_by_id->{$which} || $self->_column_index_by_short->{$which};
    defined $column or return;

    if(my $p = $args{permission})
    {   $::session->user->can_access_column($column, $p) or return undef;
    }

    $column;
}

=head2 \@columns = $doc->columns(\@which, %options);
Gets columns (by id or object) and returns ::Column objects.  This is quickly faster
when more than one column must be looked-up.
=cut

sub columns($%)
{   my ($self, $which, %args) = @_;

    return $which
        unless first { ! blessed $_ } @$which;

    my $by_id   = $self->_column_index_by_id;
    my $by_name = $self->_column_index_by_short;
    my @columns;
    foreach my $which (@$which)
    {   my $column = blessed $which ? $which : $by_id->{$which} || $by_name->{$which};
        defined $column or next;
        push @columns, $column;
    }

    if(my $p = $args{permission})
    {   my $user = $::session->user;
        @columns = grep $user->can_access_column($_, $p), @columns;
    }

    \@columns;
}


=head2 \@cols = $doc->columns_for_sheet($which);
Returns all columns which are linked to a certain sheet.  Pass sheet by
id or object.
=cut

sub columns_for_sheet($)
{   my ($self, $which) = @_;
    my $sheet_id = blessed $which ? $which->id : $which;
    my $by_id    = $self->_column_index_by_id;
    $self->columns( [ grep $_->sheet_id == $sheet_id, values %$by_id ]);
}

=head2 \@cols = $doc->columns_relating_to($which);
Returns the columns which relate to the specified column, C<$which> can be
an column-id or -object.
=cut

sub columns_relating_to($)
{   my ($self, $which) = @_;
    my $col_id = blessed $which ? $which->id : defined $which ? $which : return;
    [ grep $col_id==($_->related_field_id // 0), @{$self->all_columns} ];
}

=head2 $doc->publish_column($column);
Sheets can see each others columns, so they need to publish changes to
the layout.
=cut

sub publish_column($)
{   my ($self, $column) = @_;
    $self->_column_index_by_id->{$column->id} =
    $self->_column_index_by_short->{$column->name_short} = $column;
    $::db->schema->add_column($column->_record);
    $column;
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
Manage table "CurvalField", which contains pointers to records.
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
    my $index = $self->_column_index_by_id;
    my @childs = grep { ($_->link_parent || 0) == $pid } values %$index;
    $self->columns(@childs);
}

#--------------
=head1 METHODS: Other

=head2 $doc->column_unuse($column);
Remove a column wherever it is used.
=cut

sub column_unuse($)
{   my ($self, $column) = @_;

=pod
    $_->filter_remove_column($column)
       for grep defined, map $_->filter, @{$self->all_columns};
=cut

    $_->column_unuse($column)
       for @{$self->all_sheets};
}

=head2 $doc->document_delete;
Remove all sheets maintained by this document.
=cut

sub document_delete
{   my $self = shift;
    $_->sheet_delete for @{$self->all_sheets};
}


1;
