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

package Linkspace::Column::Curval;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Curcommon';

use Log::Report 'linkspace';

my @option_name = qw/override_permissions value_selector show_add delete_not_used/;

###
### META
###

__PACKAGE__->register_type;

sub option_names { shift->SUPER::option_names(@_, @option_names) }

###
### Instance
###

has value_selector => (
    is      => 'rw',
    isa     => sub { $_[0] =~ /^(typeahead|dropdown|noshow)$/ or panic "Invalid value_selector: $_[0]" },
    lazy    => 1,
    coerce => sub { $_[0] || 'dropdown' },
    builder => sub {
        my $self = shift;
        return 'dropdown' unless $self->has_options;
        exists $self->options->{value_selector} ? $self->options->{value_selector} : 'dropdown';
    },
    trigger => sub { $_[0]->reset_options },
);

has show_add => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    coerce  => sub { $_[0] ? 1 : 0 },
    builder => sub {
        my $self = shift;
        return 0 unless $self->has_options;
        $self->options->{show_add};
    },
    trigger => sub {
        my ($self, $value) = @_;
        $self->multivalue(1) if $value && $self->value_selector eq 'noshow';
        $self->reset_options;
    },
);

has delete_not_used => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    coerce  => sub { $_[0] ? 1 : 0 },
    builder => sub {
        my $self = shift;
        return 0 unless $self->has_options;
        $self->options->{delete_not_used};
    },
    trigger => sub { $_[0]->reset_options },
);

has set_filter => (
    is => 'rw',
);

has '+filter' => (
    builder => sub {
        my $self = shift;
        GADS::Filter->new(
            as_json => $self->set_filter,
            layout  => $self->layout_parent,
        )
    },
);

# Used to see whether we can filter yet using any filters defined for the
# curval field. If the filter contains values of the parent record, then that
# parent record needs to be set first
sub filter_view_is_ready
{   my $self = shift;
    !!$self->view;
}

has view => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_view
{   my $self = shift;
    my $view = GADS::View->new(
        instance_id => $self->refers_to_instance_id,
        filter      => $self->filter,
        layout      => $self->layout_parent,
        user        => undef,
    );
    # Replace any "special" $short_name values with their actual value from the
    # record. If sub_values fails (due to record not being ready yet), then the
    # view is not built
    return unless $view->filter->sub_values($self->layout);
    return $view;
}

# Whether this field has subbed in values from other parts of the record in its
# filter
has has_subvals => (
    is      => 'lazy',
    isa     => Bool,
    builder => sub { !! @{$_[0]->filter->columns_in_subs} },
}

# The fields that we need input by the user for this filtered set of values
has subvals_input_required => (
    is      => 'lazy',
);

sub _build_subvals_input_required
{   my $self = shift;
    my @cols = @{$self->filter->columns_in_subs};

    foreach my $col (@cols)
    {   my @disp_col_ids = map $disp->display_field_id,
           $::db->search(DisplayField => { layout_id => $col->id })->all;

        push @cols, $self->layout->column($_)
            for @{$col->depends_on}, @disp_col_ids;
    }

    my %needed = map +($_->id => $_), @cols;
    [ grep $_->userinput, values %needed ];
}

# The string/array that will be used in the edit page to specify the array of
# fields in a curval filter
has data_filter_fields => (
    is      => 'lazy',
    isa     => Str,
);

sub _build_data_filter_fields
{   my $self   = shift;
    my $fields = $self->subvals_input_required;
    grep $_->instance_id != $self->instance_id, @$fields
        and warning "The filter refers to values of fields that are not in this table";
    '[' . (join ', ', map '"'.$_->field.'"', @$fields) . ']';
}

sub _build_refers_to_instance_id
{   my $self = shift;
    my $fields_ids = $self->curval_field_ids;
    @$fields_ids or return undef;

    # Pick a random field from the selected display fields to work out the
    # parent layout
    my $random = $self->layout->column($field_ids->[0]);
    $random ? $random->instance_id : undef;
}

sub make_join
{   my ($self, @joins) = @_;
    @joins or return $self->field;

    +{
        $self->field => {
            value => {
                record_single => ['record_later', @joins],
            }
        }
    };
}

has autocurs => (
    is      => 'lazy',
    builder => sub
    {   my $id = $_[0]->id;
        [ $::db->search(Layout => { type => 'autocur', related_field => $id })->all ];
    },
);

sub write_special
{   my ($self, %options) = @_;

    my $id   = $options{id};
    my $rset = $options{rset};

    unless ($options{override})
    {
        my $layout_parent = $self->layout_parent
            or error __"Please select a table to link to";
        $self->_update_curvals(%options);
    }

    # Update typeahead option
    $rset->update({
        typeahead   => 0, # No longer used, replaced with value_selector
    });

    # Clear what may be cached values that should be updated after write
    $self->clear;
    # Re-add the layout - will be missing as a result of the clear
    $self->filter->layout($self->layout);

    # Force any warnings to be shown about the chosen filter fields
    $self->data_filter_fields unless $options{override};

    return ();
};

sub validate
{   my ($self, $value, %options) = @_;
    return 1 if !$value;
    my $fatal = $options{fatal};
    if ($value !~ /^[0-9]+$/)
    {
        return 0 if !$fatal;
        error __x"Value for {column} must be an integer", column => $self->name;
    }

    if (! $::db->get_record(Current => { instance_id => $self->refers_to_instance_id, id => $value }))
    {
        return 0 if !$fatal;
        error __x"{id} is not a valid record ID for {column}", id => $value, column => $self->name;
    }
    1;
}

sub fetch_multivalues
{   my ($self, $record_ids, %options) = @_;

    # Order by record_id so that all values for one record are grouped together
    # (enabling later code to work)
    my @values = $::db->seach(Curval => {
        'me.record_id'      => $record_ids,
        'me.layout_id'      => $self->id,
    },{
        order_by => 'me.record_id',
        result_class => 'HASH',
    })->all;

    my $records = GADS::Records->new(
        user                 => $self->override_permissions ? undef : $self->layout->user,
        layout               => $self->layout_parent,
        columns              => $self->curval_field_ids,
        limit_current_ids    => [ map $_->{value}, @values ],
        is_draft             => $options{is_draft},
        columns              => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
    );

    # We need to retain the order of retrieved records, so that they are shown
    # in the correct order within each field. This order is defined with the
    # default sort for each table
    my %retrieved; my $order;
    while (my $record = $records->single)
    {
        $retrieved{$record->current_id} = {
            record => $record,
            order  => ++$order, # store order
        };
    }

    my (@return, @single, $last_record_id);
    foreach my $v (@values)
    {
        if ($last_record_id && $last_record_id != $v->{record_id})
        {   push @return, sort { $a->{order} && $b->{order} ? $a->{order} <=> $b->{order} : 0 } @single;
            @single = ();
        }

        push @single, {
            layout_id => $self->id,
            record_id => $v->{record_id},
            value     => $v->{value} && $retrieved{$v->{value}}->{record},
            order     => $v->{value} && $retrieved{$v->{value}}->{order},
        };
        $last_record_id = $v->{record_id};
    };
    # Use previously stored order to sort records - records can be part of
    # multiple values
    push @return, sort { $a->{order} && $b->{order} ? $a->{order} <=> $b->{order} : 0 } @single;

    @return;
}

sub multivalue_rs
{   my ($self, $record_ids) = @_;
    $::db->search(Curval => {
        'me.record_id'      => $record_ids,
        'me.layout_id'      => $self->id,
    });
}

sub random
{   my $self = shift;
    $self->all_ids->[rand @{$self->all_ids}];
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Curval => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

#XXX move to Curcommon?
#XXX Unexpected side effects
sub field_values($$%)
{   my ($self, $datum, $row, %options) = @_;

    my @values;
    if($self->show_add)
    {
        foreach my $record (@{$datum_write->values_as_query_records})
        {
            $record->write(%options, no_draft_delete => 1, no_write_values => 1);
            push @{$row->_records_to_write_after}, $record
                if $record->is_edited;

            push @values, $record->current_id;
        }
    }

    push @values, @{$datum->ids};

    if($self->delete_not_used)
    {
        my @ids_deleted;
        foreach my $id_deleted (@{$datum->ids_removed})
        {
            my $is_used;
            foreach my $refers (@{$self->layout_parent->referred_by})
            {
                my $refers_layout = Linkspace::Layout->new(
                    user                     => $row->layout->user,
                    user_permission_override => 1,
                    config                   => GADS::Config->instance,
                    instance_id              => $refers->instance_id,
                );
                my $rules = GADS::Filter->new(
                    as_hash => {
                        rules     => [{
                            id       => $refers->id,
                            type     => 'string',
                            value    => $id_deleted,
                            operator => 'equal',
                        }],
                    },
                );
                my $view = GADS::View->new( # Do not write to database!
                    name        => 'Temp',
                    filter      => $rules,
                    instance_id => $refers->instance_id,
                    layout      => $refers_layout,
                    user        => undef,
                );
                my $refers_records = GADS::Records->new(
                    user    => undef,
                    view    => $view,
                    columns => [],
                    layout  => $refers_layout,
                );
                $is_used = $refers_records->count;
                last if $is_used;
            }

            if (!$is_used)
            {
                my $record = GADS::Record->new(
                    layout   => $self->layout_parent,
                );
                $record->find_current_id($id_deleted);
                $record->delete_current(override => 1);
                push @ids_deleted, $id_deleted;
            }
        }
        $datum->ids_deleted(\@ids_deleted);
    }

    map +{ value => $_ },
        @values ? @values : (undef);
}

1;
