## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Curval;

use warnings;
use srict;

use Moo;
extends 'Linkspace::Datum::Curcommon';

# follow the link
sub deref()
{   my $self = shift;
    my $column = $self->column;
    $column->refers_to_sheet->row($_[0]->value)->cell($column)->derefs;
}

1;
