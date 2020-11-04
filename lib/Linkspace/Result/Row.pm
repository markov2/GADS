## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Result::Row;

use warnings;
use strict;

package Linkspace::Result::Row;

use Log::Report 'linkspace';

use Linkspace::Result::Cell;

use Moo;

=head1 NAME
Linkspace::Result::Row - manage a row, within a result page

=head1 SYNOPSIS

=head1 DESCRIPTION

  ::Result::Row
     has many ::Result::Cell

=head1 METHODS
=cut

sub add_cell(%)
{   my $self = shift;
    my $cell = Linkspace::Result::Cell->new(@_);
    $self->{cells}{$cell->name} = $cell;
}

sub cells() { [ values %{$_[0]->{cells}} ] }

1;
