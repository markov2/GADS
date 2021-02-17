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

sub derefs() {
    my $self = shift;
    my $rev  = $self->curval_revision;
    my $cols = $self->column->curval_columns;
    [ map @{$rev->cell($_)->derefs}, @$cols ];
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
