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

package Linkspace::Results;
use Log::Report 'linkspace';

use POSIX qw(ceil);
use Moo;

with 'GADS::RecordsJoin';

=head1 NAME

Linkspace::Results - A collection of records

=head1 SYNOPSIS

   my $results = Linkspace::Results->new(
       query    => \%query,
       hits     => \@hits,
   );

=head1 DESCRIPTION

The Results object is the result of a search in sheet data.  It may even
cover information from multiple sheets.  The search is usually triggered
by applying Filter rules from a View.

=head1 METHODS: Constructors
=cut

#-------------------------
=head1 METHODS: Generic accessors

=head2 my $content = $results->content;
The content configuration which is used to produce these results.

=head2 \%query = $results->query;
Returns a HASH with configuration parameters used to run the search which
led to these results.  This may be used to generate follow-up queries.

=head2 \@hits = $results->hits;
Describes all search results.  This does not mean that these are all fully
worked out: some knowledge may need to be collected at use time.

=head2 my $limited = $results->search_limit_reached;
When set, it explains what the limit was: so both a boolean and a count.
=cut

has content => ( is => 'ro', required => 1);
has query   => ( is => 'ro', required => 1);
has hits    => ( is => 'ro', required => 1);
has search_limit_reached => ( is => 'ro', default => 0 );
has used_column_grouping => ( is => 'ro', default => 0 );

has aggregated_results   => ( is => 'ro' );
has columns => ( is => 'ro' );   #XXX $query->view->columns?

has sheet   => ( is => 'lazy', builder => sub { $_[0]->content->sheet } );

=head2 my $date = $results->are_historic;
True when the results do not reflect the latest state of the sheet content,
but taken from an earlier moment.  (Rewind)
=cut

sub are_historic { $_[0]->query->{rewind} }

=head2 my $count = $results->nr_pages($page_size);
Returns the number of pages, given the specified preferred page size.
Some conditions may not support multipage outcome.
=cut

sub nr_pages($)
{   my ($self, $page_size) = @_;
    $self->used_column_grouping ? 1 : ceil( @{$_[0]->hits} / $page_size );
}

sub has_rag_column() { !! first { $_->type eq 'rag' } @{$_[0]->columns} }

=head2 \@rows = $results->rows(%select);
Returns ::Result::Rows for the selected page.  Those are expensive to compute
and not cached (because they may consume a lot of memory)
=cut

sub rows(%)
{   my ($self, %args) = @_;
    my $page = ($args{page} || 1) -1;

    my $hits = $self->hits;
    my @hits = @$hits;
    if(my $page_size = $args{page_size})
    {   splice @hits, 0, $page * $page_size;
        $#hits = $page_size -1;
    }

    my %need_row = map +($_->{current_id} => $_), grep !$_->{row}, @hits;

    # Need to implement bulk loads later
    foreach my $current_id (keys %need_row)
    {   my $row =
        $need_row{$current_id}{row} = $row;
    }
}


=head2 \@show = $result->presentation(%select);
Returns the selected rows in presentable form.
=cut

sub presentation(%) {
    my $self  = shift;
    my $view  = $self->query->{view};
    my $current_group_id = $view ? $view->first_grouping_column_id : undef;
    
    my @show = map $_->presentation(group => $current_group_id, @_),
         @{$self->rows(@_)};
    
    \@show;
}

sub aggregate_presentation
{   my $self   = shift;
    
    my $row = $self->aggregated_results
        or return undef;

    my @presentation = map {
        my $cell = $row->cell($_);
        $cell && $_->presentation(datum_presentation => $cell->presentation)
    } @{$self->columns_view};
    
     +{ columns => \@presentation };
}

#--------------------------------
=head1 METHODS: Paging

=head2 $results->window(%settings);
Change the window of search results which are shown in this page view.  Possible
parameters are C<page_number> (starts at zero), C<page_length> (minimal 1),
=cut

sub window(%)
{   my ($self, %args) = @_;
    ...
}

=head2 $results->next_page;
Move the result window after the current page.
=cut

sub next_page()
{
}

sub all_rows()
{
}

1;
