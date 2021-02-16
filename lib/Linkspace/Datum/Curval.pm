## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Curval;

use Log::Report 'linkspace';

use Linkspace::Util  qw(to_id);

use Moo;
extends 'Linkspace::Datum::Curcommon';

sub _unpack_values($$$%)
{   my ($class, $column, $old_values, $values, %args) = @_;
    [ map to_id($_), @$values ];
}

sub deref() {
    my $self = shift;
    my $curval_columns = $self->column->curval_columns;
    @$curval_columns==1 or panic "Can only deref curvals which are single value";
    $self->curval_revision->cell($curval_columns->[0])->derefs;
}

has curval_revision => (
   is      => 'lazy',
   builder => sub
     { my $self   = shift;
       my $rewind = $self->revision->row->content->rewind;
       $self->column->curval_sheet->content(rewind => $rewind)
           ->row($self->value)->current;
     },
);

has curval_cells => (
   is      => 'lazy',
   builder => sub
     { my $self = shift;
       my $rev  = $self->curval_revision;
       [ map $rev->cell($_), @{$self->column->curval_columns} ];
     },
);

sub curval_datums() { [ map @{$_->datums}, @{$_[0]->curval_cells} ] }

sub values { [ map $_->value, @{$_[0]->curval_datums} ] }

1;
