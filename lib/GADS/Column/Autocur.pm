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

package GADS::Column::Autocur;

use GADS::Config;
use GADS::Records;
use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Column::Curcommon';

has '+option_names' => (
    default => sub { [qw/override_permissions/] },
);

has '+multivalue' => (
    coerce => sub { 1 },
);

has '+userinput' => (
    default => 0,
);

has '+no_value_to_write' => (
    default => 1,
);

has '+value_field' => (
    default => 'id',
);

# Dummy function so that value_selector() can be called from a curcommon class
sub value_selector { '' }

sub _build_sprefix { 'current' };

sub _build_refers_to_instance_id
{   my $self = shift;
    $self->related_field or return undef;
    $self->related_field->instance_id;
}

has related_field => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $self = shift;
        # Under normal circumstances we will have a full layout with columns
        # built. If not, fall back to retrieving from database. The latter is
        # needed when initialising the schema in GADS::DB::setup()
        $self->layout->column($self->related_field_id)
            || $self->schema->resultset('Layout')->find($self->related_field_id);
    }
);

has related_field_id => (
    is      => 'rw',
    isa     => Maybe[Int], # undef when importing and ID not known at creation
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->_rset && $self->_rset->get_column('related_field');
    },
    trigger => sub {
        my ($self, $value) = @_;
        $self->clear_related_field;
    },
);

sub _build_related_field_id
{   my $self = shift;
    $self->related_field->id;
}

# XXX At some point these individual refers_from properties should be replaced
# by an object representing the whole column. That will be easier if/when the
# column object can be easily generated with an ID value
has refers_from_field => (
    is => 'lazy',
);

sub _build_refers_from_field
{   my $self = shift;
    "field".$self->related_field->id;
}

has refers_from_value_field => (
    is => 'lazy',
);

sub _build_refers_from_value_field
{   my $self = shift;
    "value";
}

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

sub write_special
{   my ($self, %options) = @_;

    return if $options{override};

    my $rset = $options{rset};

    $self->related_field_id
        or error __x"Please select a field that refers to this table";

    $rset->update({
        related_field => $self->related_field_id,
    });

    $self->_update_curvals(%options);

    # Clear what may be cached values that should be updated after write
    $self->clear;

    return ();
};

# Autocurs are defined as not user input, so they get updated during
# update-cached. This makes sure that it does nothing silently
sub update_cached {}

# Not applicable for autocurs - there is no filtering for an autocur column as
# there is with curvals
sub filter_view_is_ready
{   my $self = shift;
    return 1;
}

has view => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub {},
);

sub fetch_multivalues
{   my ($self, $record_ids) = @_;

    my @values = $self->multivalue_rs($record_ids)->all;
    my $records = GADS::Records->new(
        user                 => $self->override_permissions ? undef : $self->layout->user,
        layout               => $self->layout_parent,
        schema               => $self->schema,
        columns              => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
        limit_current_ids    => [map { $_->{record}->{current_id} } @values],
        include_children     => 1, # Ensure all autocur records are shown even if they have the same text content
    );
    my %retrieved;
    while (my $record = $records->single)
    {
        $retrieved{$record->current_id} = $record;
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
        join => {
            record_single => 'record_later',
        },
    })->get_column('record_single.id')->as_query;

    $self->schema->resultset('Curval')->search({
        'me.record_id' => { -in => $subquery },
        'me.layout_id' => $self->related_field->id,
        'records.id'   => \@record_ids,
    },{
        prefetch => [
            'record',
            { value => 'records' },
        ],
        result_set => 'HASH',
    });

}

around export_hash => sub {
    my $orig = shift;
    my $self = shift;
    my $hash = $orig->($self, @_);
    $hash->{related_field_id} = $self->related_field_id;
    $hash;
};

around import_after_all => sub {
    my $orig = shift;
    my ($self, $values, %options) = @_;
    my $mapping = $options{mapping};
    my $report = $options{report_only};
    my $new_id = $mapping->{$values->{related_field_id}};
    notice __x"Update: related_field_id from {old} to {new}", old => $self->related_field_id, new => $new_id
        if $report && $self->related_field_id != $new_id;
    $self->related_field_id($new_id);
    $orig->(@_);
};

sub how_to_link_to_record {
	my ($self, $schema) = @_;
    my $related_field_id = $self->related_field->id; # "compile"-time

    my $subquery = $schema->resultset('Current')->search({
        'record_later.id' => undef,
    },{
        join => {
            record_single => 'record_later'
        },
    })->get_column('record_single.id')->as_query;

    my $linker = sub { 
        my ($other, $me) = ($_[0]->{foreign_alias}, $_[0]->{self_alias});
        
        return {
            "$other.value"     => { -ident => "$me.current_id" },
            "$other.layout_id" => $related_field_id, 
            "$other.record_id" => { -in => $subquery },
        };
    };

    (Curval => $linker);
}

1;
