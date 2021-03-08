## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Row::Cell;

use Log::Report    'linkspace';
use HTML::Entities qw(encode_entities);

use Linkspace::Datum           ();;
#use Linkspace::Datum::Autocur  (); # Moo does not want these inside Datum.pm
use Linkspace::Datum::Calc     ();
use Linkspace::Datum::Count    ();
use Linkspace::Datum::Curval   ();
use Linkspace::Datum::Date     ();
use Linkspace::Datum::Daterange();
use Linkspace::Datum::Enum     ();
use Linkspace::Datum::File     ();
use Linkspace::Datum::ID       ();
use Linkspace::Datum::Integer  ();
use Linkspace::Datum::Person   ();
use Linkspace::Datum::Rag      ();
use Linkspace::Datum::Serial   ();
use Linkspace::Datum::String   ();
use Linkspace::Datum::Tree     ();

#!!! This really needs to be fast: I do not use Moo for cells

=head1 NAME

Linkspace::Row::Cell - one datum in a sheet

=head1 DESCRIPTION

A cell is a object which connects a datum to its location: a row-revision
in a row in a sheet, with its content type.

B<WARNING> There are (potentially) zillion of datums, so on some places,
short-cuts are taken which break abstraction for the sake of performance.

=head1 METHODS: Constructors

=cut

# %args are
#     column       Linkspace::Column object
#     revision     Linkspace::Row::Revision object
#     datums       Linkspace::Datum objects
# The datum can be specified as already prepared object, or as HASH raw
# from the database.

use overload
    '""'     => 'as_string',
    bool     => sub { !! @{$_[0]->datums} },
    fallback => 1;

sub new($%)
{   my ($class, %args) = @_;
    bless \%args, $class;
}

sub is_linked { 0 }

sub text_all
{   my $self = shift;
    my $column = $self->column;
    $self->{text_all} ||= [ map $column->datum_as_string($_), @{$self->datums} ];
}

sub match_values { [ map $_->match_value, @{$_[0]->datums} ] }
sub as_string    { join ', ', @{$_[0]->text_all} }
sub as_integer   { $_[0]->{datums}[-1]->as_integer($_[0]) }
sub html         { encode_entities $_[0]->as_string }
sub html_form    { $_[0]->text_all }

sub column       { $_[0]->{column} }
sub revision     { $_[0]->{revision} }
sub row          { $_[0]->{row}    ||= $_[0]->revision->row }
sub sheet        { $_[0]->{sheet}  ||= $_[0]->revision->sheet }
sub layout       { $_[0]->{layout} ||= $_[0]->sheet->layout }

#-------------
=head1 METHODS: Handling datums

=head2 my $datum = $cell->datum;
Returns the datum which is kept in the cell.  Croaks when this is a
cell in a multivalue column.  May return C<undef> for a cell in a
column with optional values.
=cut

sub datum()
{   my $self = shift;
    ! $self->column->is_multivalue or panic;
    $self->{datums}[0];
}

=head2 \@datums = $cell->datums;
Returns all datums in this cell.  Also when this is not a multivalue
column, it still returns an ARRAY.
=cut

sub datums() { $_[0]->{datums} || [] }

=head2 \@datums = $cell->derefs;
Returns all datums.  When the datum is a curval, it returns the value it
points to (recursively) which can be more than one datum.
=cut

sub derefs() { [ map @{$_->derefs}, @{$_[0]->datums} ] }

=head2 $cell->is_blank;
Returns true when there not a single useful value written to this cell. Be warned
that an empty value (like a blank string) is a useful value.
=cut

sub is_blank { ! @{$_[0]->{datums} || []} }

=head2 my $value = $cell->value;
Returns the only value which in this cell.

Only use this when you are sure that the column cannot be a multipart, like for
internal columns, otherwise you will get a (planned) panic.
=cut

sub value  { my $d = $_[0]->datum; $d ? $d->value : undef }

=head2 $cell->remove_datums;
Blank the cell: all db records get removed.
=cut

sub remove_datums()
{   my $self = shift;
    my $datums = delete $self->{datums};
    $_->_datum_delete($self) for @$datums;
}

=head2 \@values = $cell->values;
Returns the values in all of the datums.
=cut

sub values { [ map $_->value, @{$_[0]->datums} ] }

=head2 $cell->same_values(\@datums);
Returns whether the two cells have exactly the same values.
=cut

sub same_values
{   my ($self, $other_datums) = @_;
    my $my_vals    = $self->values;
    my @other_vals = map $_->value, @$other_datums;

    return 0 if @$my_vals != @other_vals;
    return 1 if @other_vals==1 && $my_vals->[0] eq $other_vals[0];
    
    my %need = map +($_ => 1), @$my_vals;
    delete $need{$_} for @other_vals;
    ! keys %need;
}

=head2 \%h = $cell->for_code(%options);
Create a datastructure to pass column information to Calc logic.
Curcommon offers some options.

It is a pity, but the handling of multivalues is not consistent.
=cut

sub for_code(%)
{   my ($self, %args) = @_;

    my $datums = $self->datums;
    my @r = map $_->_value_for_code($self, $cell, \%args), @$datums;

    if($datums->[0]->isa('Linkspace::Datum::Tree'))
    {   @r or push @r, +{  value => undef, parents => {} };
    }
    elsif($datums->[0]->isa('Linkspace::Datum::Enum'))
    {   return $self->column->is_multivalue
          ? +{ text => $self->as_string, values => \@r }
          : $self->as_string;
    }

    #XXX Not smart to pass multival datums in an inconsitent way.
    #XXX Kept for backwards compatibility.
    $self->column->is_multivalue && @r > 1 ? \@r : $r[0];
}

sub is_awaiting_approval { $_[0]->{is_awaiting_approval} }

sub datum_type
{   my $self  = shift;
    my $datum = $_[0]->{datums}[0];
    $datum && $datum->isa('Linkspace::Datum::Count') ? 'count' : $_[0]->column->type;
}

sub presentation
{   my $self   = shift;
    my $datums = $self->datums;

    my $show   =
     +{ type         => $self->datum_type,
        value        => $self->as_string,
        filter_value => $self->filter_value,
        blank        => $self->is_blank,
        is_displayed => $self->is_displayed,
      };

    $_->presentation($show) for @$datums;
    $show;
}

sub filter_value
{   my $datum = ($_[0]->datums)[0];
    $datum ? $datum->filter_value : undef;
}

sub value_hash
{   my $self = shift;
    my $column = $self->column;
    my $type   = $column->type;

    if($type eq 'enum' || $type eq 'tree')
    {   my @hs = map $_->value_hash($column), @{$self->datums};
        #XXX Repacking usually a bad idea
        return
         +{ ids     => [ map $_->{id}, @hs ],
            text    => [ map $_->{text}, @hs ],
            deleted => [ map $_->{deleted}, @hs ],
          };
    }

    panic;
}

sub deleted_values()
{   my $self = shift;
    my $column = $self->column;

    if($column->type eq 'enum')
    {   return [ grep $_->{deleted}, map $_->value_hash($column), @{$self->datums} ];
    }
    panic;
}

=head2 my $repr = $cell->sortable;
Represent the values in the cell in such a way that it can be sorted via 'cmp'.
Usually, all datums are used, however that's not possible for all kinds of datums
(especially date related fields)
=cut

sub sortable()
{   # The datums are already sorted, so we only need to return their values
    join ';', map $_->sortable, @{$_[0]->datums};
}

# Most values are ids; this builds an index for them.
sub id_hash { +{ map +( $_->value => 1), @{$_[0]->datums} } }  #XXX used?

# Tree
sub ids_as_params { join '&', map $_->value, @{$_[0]->datums} }  #XXX used?

sub is_displayed() { $_[0]->column->is_displayed_in($_[0]->revision) }

1;
