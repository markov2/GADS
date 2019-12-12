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

package Linkspace::Sheets;
use Moo ();

use Log::Report  'linkspace';
use Scalar::Util qw(weaken);
use List::Util   qw(first);

use Linkspace::Sheet ();

=head1 NAME
Linkspace::Sheets - manages sheets for one site

=head1 SYNOPSIS

  my $sheets  = $::session->site->sheets;
  my $all_ref = $sheets->all_sheets;

=head1 DESCRIPTION

=head1 METHODS: Constructors
M

=head2 my $sheets = Linkspace::Sheets->new(%options);
Required is C<site>.
=cut

has site => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);


=head1 METHODS: Sheet management

=head2 my @all = $sheets->all_sheets;
Return all sheets, even those which the session user is not allowed to access.
They are sorted by name (case insensitive).
=cut

has all_sheets => (
   is      => 'lazy',
   isa     => ArrayRef,
   builder => sub
   {   my $self   = shift;
       my @sheets = map Linkspace::Sheet->fromInstance($_),
           $self->site->resultset('Instance')->all;

       [ sort { fc($a->name) cmp fc($b->name) } @sheets ];
   }
}


=head2 my $sheet = $sheets->sheet($which);
Get a single sheet, C<$which> may be specified as name, short name or id.
=cut

has _sheet_index => (
    is      => 'lazy',
    isa     => HashRef,
    builder => sub
    {   my $self = shift;
        my %index;
        foreach my $sheet ( @{$self->all_sheets} )
        {   $index{$sheet->id}         =
            $index{'table'.$sheet->id} =
            $index{$sheet->name}       =
            $index{$sheet->short_name} = $sheet;
        }
        \%index;
    }
);

sub sheet($)
{   my ($self, $which) = @_;
    return $which
        if blessed $which && $which->isa('Linkspace::Sheet');

    $self->_sheet_index->{$which};
}


=head2 $sheets->delete_sheet($which);
Remove the indicated sheet.
=cut

sub delete_sheet($)
{   my ($self, $which) = @_;

    my $sheet = $self->sheet($which)
        or return;

    my $site  = $self->site;
    $sheet->delete($site);
    $site->structure_changed;
    $self;
}

=head2 my $sheet = $sheets->first_homepage
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


=head2 my $col_info = $sheets->column_info_by_id($id);
=cut

sub column_by_info_id($)
{   my ($self, $id) = @_;
    $self->_column_info_index->{$id};
}


=head2 my $layout = $sheets->layout_for_sheet($sheet);
=cut

has _layout_index => (
    is => 'ro',
    default => +{},
);

sub layout_for_sheet($)
{   my ($self, $sheet) = @_;
    my $layout = $self->_layout_index->{$sheet->id};
    return $layout if $layout;

#XXX
    my @cols = grep $_->instance_id == $sheet_id, @{$self->_column_info};
    my $layout = Linkspace::Layout->revive(sheet => $sheet, columns =>C \@cols);

    $self->_layout_index->{$sheet->id} = $layout;
}

1;
