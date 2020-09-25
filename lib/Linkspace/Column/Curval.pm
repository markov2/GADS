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

use Log::Report 'linkspace';
use Linkspace::Util qw/uniq_objects/;
use Scalar::Util    qw/blessed/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Curcommon';

my @options = (
    override_permissions => 0,          #XXX still needed?
    value_selector       => 'dropdown',
    show_add             => 0,
    delete_not_used      => 0
);

###
### META
###

__PACKAGE__->register_type;

sub db_field_extra_export { [ qw/filter/ ] }
sub option_defaults { shift->SUPER::option_defaults(@_, @options) }
sub form_extras { [ qw/refers_to_sheet_id filter/ ], [ 'curval_field_ids' ] }

###
### Class
###

###
### Instance
###

#XXX Create with refers_to_sheet and related_column.
#XXX curval_field_ids defaults to all non-internal columns in refers_to_sheet

sub _validate($)
{   my ($thing, $update) = @_;
    $self->SUPER::_validate($update);

    if(my $opt = $update->{options})
    {   $self->{is_multivalue}
          =  exists $opt->{show_add} && $opt->{value_selector} eq 'noshow';
    }
}

sub value_selector  { $_[0]->options->{value_selector} // 'dropdown' }
sub show_add        { $_[0]->options->{show_add} // 0 }
sub delete_not_used { $_[0]->options->{delete_not_used} // 0 }

# Whether this field has subbed in values from other parts of the record in its
# filter
has has_subvals => (
    is      => 'lazy',
    isa     => Bool,
    builder => sub { my $c = $_[0]->filter->column_names_in_subs; !!@$c },
}

# The fields that we need input by the user for this filtered set of values
has subvals_input_required => (
    is      => 'lazy',
);

sub _build_subvals_input_required
{   my $self   = shift;
    my $layout = $self->layout;
    my $col_names = $self->filter->column_names_in_subs;

    foreach my $col_name (@$col_names)
    {   my $col = $layout->column($col_name) or next;

        my @disp_col_ids = map $_->display_field_id,
            $::db->search(DisplayField => { layout_id => $col->id })->all;

        #XXX permission => 'write' ?
        push @$cols, map $layout->column($_),
            @{$col->depends_on_ids}, @disp_col_ids;
    }

    [ grep $_->userinput, uniq_objects \@cols ];
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
    my $my_sheet_id = $self->sheet_id;
    first { $_->instance_id != $my_sheet_id } @$fields
        and warning "The filter refers to values of fields that are not in this table";
    '[' . (join ', ', map '"'.$_->field.'"', @$fields) . ']';
}

# Pick a random field from the selected display fields
# (to work out the parent layout)

sub related_sheet_id()
{   my $random = $_[0]->curval_fields->[0];
    $random ? $random->sheet_id : undef;
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

sub autocurs()
{   my $document = shift->document;
    [ grep $_->type eq 'autocur', $document->columns_relating_to($self) ];
}

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

    # Force any warnings to be shown about the chosen filter fields
    $self->data_filter_fields unless $options{override};

    return ();
};

sub _is_valid_value($)
{   my ($self, $value) = @_;

    $value =~ /^[0-9]+$/)
        or error __x"Value for {column} must be an integer", column => $self->name;

    $self->sheet->content->row($id)
        or error __x"Current {id} is not a valid record ID for {column}",
        id => $value, column => $self->name;

    $value;
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

    my $user = $self->override_permissions ? undef : $::->session->user;
    my $page = $self->sheet_parent->content->search(
        user              => $self->override_permissions ? undef : $self->layout->user,
        limit_current_ids => [ map $_->{value}, @values ],
        is_draft          => $options{is_draft},
        columns           => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
    );

    # We need to retain the order of retrieved records, so that they are shown
    # in the correct order within each field. This order is defined with the
    # default sort for each table
    my %retrieved; my $order;
    while(my $row = $page->next_row)
    {   $retrieved{$row->current_id} = +{
            record => $tow,
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
            {   my $refers_sheet = $::session->site->sheet($refers->sheet_id);

                my $filter = { rule => {
                        id       => $refers->id,
                        type     => 'string',
                        operator => 'equal',
                        value    => $id_deleted,
                }};

                my $refers_page = $refers_sheet->content->search(
                    user    => undef,
                    filter  => $filter,
                    columns => [],
                );

                $is_used = $refers_page->count;
                last if $is_used;
            }

            if(!$is_used)
            {   $sheet->content->current->row_delete($id_deleted);
                push @ids_deleted, $id_deleted;
            }
        }
        $datum->ids_deleted(\@ids_deleted);
    }

    map +{ value => $_ },
        @values ? @values : (undef);
}

sub refers_to_sheet($)
{   my ($self, $which) = @_;
    my $sheet_id = blessed $which ? $which->id : $which;
    grep $_->child->sheet_id != $sheet_id, $self->curval_fields_parents;
}

1;
