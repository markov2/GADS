package Linkspace::Page::Row;

use warnings;
use strict;

use Moo;
extends 'Linkspace::DB::Table';

use Log::Report 'linkspace';

=head1 NAME
Linkspace::Page::Row - manage a row, within a result page

=head1 SYNOPSIS
=head1 DESCRIPTION
=cut

sub has_rag_column() { !! first { $_->type eq 'rag' } @{$_[0]->columns_view} }

has is_grouping => (
    is => 'ro',
);

has group_cols => (
    is => 'ro',
);

1;
