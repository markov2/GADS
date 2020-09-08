=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

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

package Linkspace::Page;

use Data::Dumper qw/Dumper/;
use DateTime;
use DateTime::Format::Strptime qw( );
use DBIx::Class::Helper::ResultSet::Util qw(correlate);
use GADS::Config;
use GADS::Graph::Data;
use GADS::Record;
use GADS::Timeline;
use GADS::View;
use HTML::Entities;
use Log::Report 'linkspace';
use POSIX qw(ceil);
use Scalar::Util qw(looks_like_number);
use Text::CSV::Encoded;
use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::DateTime qw/DateAndTime/;

with 'GADS::RecordsJoin';

=head1 NAME

Linkspace::Page - A collection of records

=head1 SYNOPSIS

   my $page = Linkspace::Page->new(
       nr       => 1,
       query    => $query,
   );

=head1 DESCRIPTION

A Page is the result of a search in sheet data.  It may even cover information
from multiple sheets.  The search is usually triggered by applying Filter
rules from a View.

=head1 METHODS: Constructors
=cut

#-------------------------
=head1 METHODS: Generic accessors

=head2 my $sheet = $page->sheet;
The main sheet used to produce these results.  Sequential searches will take place
via that same sheet.
=cut

has sheet => ( is => 'ro', required => 1);

=head2 my $nr = $page->nr;
Pages start with number 1.
=cut

has nr => ( is => 'ro', required => 1);

=head2 \@ids = $page->all_row_ids;
Returns the ids for all rows which were hit by the query.
=cut

has all_row_ids => (is => 'ro', required => 1);

=head2 my $count = $page->nr_pages;
Returns the number of pages, where this page is one of.
=cut

sub nr_pages { @{$_[0]->hits} / $_[0]->page_size }

sub presentation() {
    my $self  = shift;
    my $view  = $self->view;
    my $current_group_id = $view ? $view->first_grouping_column_id : undef;
    
    my @show = map $_->presentation(group => $current_group_id, @_),
         @{$self->results};
    
    \@show;
}

sub aggregate_presentation
{   my $self   = shift;
    
    my $record = $self->aggregate_results
        or return undef;

    my @presentation = map {
        my $field = $record->field($_);
        $field && $_->presentation(datum_presentation => $field->presentation)
    } @{$self->columns_view};
    
     +{ columns => \@presentation };
}

#--------------------------------
=head1 METHODS: Paging

=head2 $page->window(%settings);
Change the window of search results which are shown in this page view.  Possible
parameters are C<page_number> (starts at zero), C<page_length> (minimal 1),
=cut

sub window(%)
{   my ($self, %args) = @_;
    ...
}

=head2 $page->next_page;
Move the result window after the current page.
=cut

sub next_page()
{
}

sub all_rows()
{
}

1;
