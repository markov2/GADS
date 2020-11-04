## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Row::Draft;

use Moo;
extends 'Linkspace::Row';

sub is_draft { 1 }

has draftuser => (
    is      => 'lazy',
    builder => sub { $_[0]->site->users->user($_[0]->draftuser_id) },
);

1;
