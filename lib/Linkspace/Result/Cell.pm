## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Result::Cell;

#!!! FAST
sub new(@) { my $class = shift; bless { @_ }, $class }

sub is_grouping() { $_[0]->{is_grouping} }

sub name()   { $_[0]->{name} }
sub datums() { $_[0]->{datums} }
sub column() { $_[0]->{column} }

1;
