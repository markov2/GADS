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

package Linkspace::Documents;
use Moo ();

use Log::Report  'linkspace';
use Scalar::Util qw(weaken);
use List::Util   qw(first);

use Linkspace::Document ();

=head1 NAME
Linkspace::Documents - manages sheets for one site

=head1 SYNOPSIS

  my $doc     = $::session->site->document;
  my $all_ref = $doc->all_sheets;

=head1 DESCRIPTION

=head1 METHODS: Constructors
M

=head2 my $doc = Linkspace::Documents->new(%options);
Required is C<site>.
=cut

has site => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);


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
       my @sheets = map Linkspace::Document->from_record($_,
           document => $self,
       ), $self->site->resultset('Instance')->all;

       [ sort { fc($a->name) cmp fc($b->name) } @sheets ];
   }
}


=head2 my $sheet = $doc->sheet($which);
Get a single sheet, C<$which> may be specified as name, short name or id.
=cut

sub _sheet_index_update($$$)
{   my ($index, $sheet, $to) = @_;
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
    return $which
        if blessed $which && $which->isa('Linkspace::Document');

    $self->_sheet_index->{$which};
}


=head2 $doc->delete_sheet($which);
Remove the indicated sheet.
=cut

sub delete_sheet($)
{   my ($self, $which) = @_;

    my $sheet = $self->sheet($which)
        or return;

    _sheet_index_update $self->_sheet_index, $sheet, undef;
    $sheet->delete;

    $self->site->structure_changed;
    $self;
}

=head2 my $new_sheet = $doc->update_sheet($sheet, \%changes);
When a sheet gets updated, it may need result in a new sheet.
=cut

sub update_sheet($$)
{   my ($self, $sheet, $changes) = @_;
    my $new = $sheet->update($changes);
    return $sheet if $new==$sheet;

    my $index = $self->_sheet_index;
    _sheet_index_update $index, $sheet, undef;
    _sheet_index_update $index, $new, $new;
    $new;
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


=head1 METHODS: Set of columns

In the original design, column knowledge was limited to single sheets: when
you were viewing one sheet (with a certain layout), you could only access
those columns.  However: cross sheet references are sometimes required.
=cut

has _column_info => (
    is  => 'lazy',
    isa => ArrayRef, 
    builder => sub { Linkspace::Layout->load_columns($_[0]) },
);

has _column_info_index => (
    is  => 'lazy',
    isa => HashRef,
    builder => sub {  +{ map +($_->id => $_), $_[0]->_column_info } },
);

has _column_index => (
    is  => 'ro',
    isa => HashRef,
    default => +{},
);


=head2 my $col_info = $doc->column_info_by_id($id);
=cut

sub column_by_info_id($) { $_[0]->_column_info_index->{$_[1]} }


=head1 METHODS: Layout management

=head2 my $layout = $doc->layout_for_sheet($sheet);
The layout gets attached to a sheet on the moment it gets used.
=cut

sub layout_for_sheet($)
{   my ($self, $sheet) = @_;

    my $sheet_id = $sheet->id;
    my @cols = grep $_->instance_id == $sheet_id, @{$self->_column_info};
    Linkspace::Layout->for_sheet($sheet, columns => \@cols);
}

1;
