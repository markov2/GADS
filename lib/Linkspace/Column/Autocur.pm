## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Autocur;
use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column::Curcommon';

#XXX From view/layout.tt:
#XXX Automatic value of other sheet's references to this one

my @options = (
    override_permissions => 0,
);

###
### META
###

__PACKAGE__->register_type

sub db_field_extra_export { [ 'related_column_id' ] }
sub form_extras      { [ 'related_field_id' ], [ 'curval_field_ids' ] }
sub option_defaults  { shift->SUPER::option_defaults(@_, @options) }
sub is_userinput     { 0 }
sub value_to_write   { 0 }
sub value_field      { 'id' }

#XXX related_column names wrt refers_to_sheet
#XXX curval_columns wrt curval_sheet

###
### Class
###

sub _remove_column($) {}  # block second call to base_class

###
### Instance
###

sub sprefix        { 'current' };

### Curcommon types

sub value_selector { '' }

sub make_join
{   my ($self, @joins) = @_;
    +{
        $self->field => {
            record => {
                current => {
                    record_single => ['record_later', @joins],
                }
            }
        }
    };
}

# Autocurs are defined as not user input, so they get updated during
# update-cached. This makes sure that it does nothing silently
sub update_cached {}

# Not applicable for autocurs - there is no filtering for an autocur column as
# there is with curvals
sub filter_view_is_ready { 1 }

has view => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {},
);

sub fetch_multivalues
{   my ($self, $record_ids) = @_;

    my @values = $self->multivalue_rs($record_ids)->all;
    my @current_ids = map $_->{record}{current_id}, @values;

    my $page   = $self->parent_sheet->content->search(
        columns           => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
        limit_current_ids => \@current_ids,
        include_children  => 1, # Ensure all autocur records are shown even if they have the same text content
    );

    my %retrieved;
    while(my $row = $page->next_row)
    {   $retrieved{$row->current_id} = $row;
    }

    # It shouldn't happen under normal circumstances, but there is a chance
    # that a record will have multiple values of the same curval. In this case
    # the autocur will contain multiple values, so we de-duplicate here.
    my (@v, %done);
    foreach (@values)
    {   my $cid = $_->{record}->{current_id};
        next if $done{$cid}++ ||  ! exists $retrieved{$cid};

        push @v, +{
            layout_id => $self->id,
            record_id => $_->{value}->{records}->[0]->{id},
            value     => $retrieved{$cid},
        };
    }
    return @v;
}

sub multivalue_rs
{   my ($self, $record_ids) = @_;

    # If this is called with undef record_ids, then make sure we don't search
    # for that, otherwise a large number of unreferenced curvals could be
    # returned
    my @record_ids = grep defined $_, @$record_ids;
    my $subquery = $::db->search(Current => {
        'record_later.id' => undef,
    },{
        join => { record_single => 'record_later' },
    })->get_column('record_single.id')->as_query;

    $::db->search(Curval => {
        'me.record_id' => { -in => $subquery },
        'me.layout_id' => $self->related_field_id,
        'records.id'   => \@record_ids,
    },{
        prefetch => [
            'record',
            { value => 'records' },
        ],
        result_set => 'HASH',
    });

}

sub how_to_link_to_record {
	my ($self) = @_;
    my $related_field_id = $self->related_field_id;

    my $subquery = $::db->search(Current => {
        'record_later.id' => undef,
    },{
        join => { record_single => 'record_later' },
    })->get_column('record_single.id')->as_query;

    # Reused
    my $linker = sub { 
        my ($other, $me) = ($_[0]->{foreign_alias}, $_[0]->{self_alias});

        return +{
            "$other.value"     => { -ident => "$me.current_id" },
            "$other.layout_id" => $related_field_id, 
            "$other.record_id" => { -in => $subquery },
         };
    };

    (Curval => $linker);
}

1;
