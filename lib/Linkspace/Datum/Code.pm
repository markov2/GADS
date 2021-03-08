## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Code;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

=pod

sub _build_vars
{   my $self = shift;
    # Ensure recurse-prevention information is passed onto curval/autocurs
    # within code values
    $self->values_by_shortname($self->record,
        already_seen_code => $self->already_seen_code,
        level             => $self->already_seen_level,
        names             => [ $self->column->params ],
    );
}

sub values_by_shortname
{   my ($self, $row, %args) = @_;
    my $names = $args{names};

    my %index;
    foreach my $name (@$names)
    {   my $col   = $self->layout->column($name) or panic $name;
        my $cell  = $row->cell($col);
        my $linked = $col->link_parent;

        my $cell_base
           = $cell->is_awaiting_approval ? $cell->old_values
           : $linked && $cell->old_values # linked, and value overwritten
           ? $cell->oldvalue
           : $cell;

        # Retain and provide recurse-prevention information. See further
        # comments in Linkspace::Column::Curcommon
        my $already_seen_code = $args{already_seen_code};
        $already_seen_code->{$col->id} = $args{level};

        $index{$name} = $cell_base->for_code(
           already_seen_code  => $already_seen_code,
           already_seen_level => $args{level} + ($col->is_curcommon ? 1 : 0),
        );
    };
    \%index;
}

=cut

1;
