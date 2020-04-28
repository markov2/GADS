=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

package Linkspace::Column::Autocur;
use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column::Curcommon';

###
### META
###

INIT { __PACKAGE__->register_type }

sub form_extras    { [ qw/related_field_id/ ], [ 'curval_field_ids' ] }
sub option_names   { shift->SUPER::option_names(@_, qw/override_permissions/ ) }
sub userinput      { 0 }
sub value_to_write { 0 }
sub value_field    { 'id' }

###
### Class
###

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
    my $records = GADS::Records->new(
        layout               => $self->layout_parent,
        columns              => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
        limit_current_ids    => [ map $_->{record}{current_id}, @values ],
        include_children     => 1, # Ensure all autocur records are shown even if they have the same text content
    );
    my %retrieved;
    while (my $record = $records->next)
    {   $retrieved{$record->current_id} = $record;
    }

    # It shouldn't happen under normal circumstances, but there is a chance
    # that a record will have multiple values of the same curval. In this case
    # the autocur will contain multiple values, so we de-duplicate here.
    my @v; my %done;
    foreach (@values)
    {
        my $cid = $_->{record}->{current_id};
        next unless exists $retrieved{$cid};
        push @v, +{
            layout_id => $self->id,
            record_id => $_->{value}->{records}->[0]->{id},
            value     => $retrieved{$cid},
        } unless $done{$cid};
        $done{$cid} = 1;
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

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_, related_field_id => $self->related_field_id);
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
