## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Curval;

use Log::Report 'linkspace';

use Linkspace::Util qw/is_valid_id to_id/;

use Moo;
extends 'Linkspace::Column::Curcommon';

my @options =
  ( value_selector  => 'dropdown',
    show_add        => 0,
    delete_not_used => 0,
  );

=head1 DESCRIPTION
The curval Datum contains a row_id.  The related curval Column knows in which
sheet we access the row and which columns in that row are to be included.

One curval Cell can contain multiple row references: one per Datum (standard
multivalue), but each

=cut

###
### META
###

__PACKAGE__->register_type;

sub datum_class { 'Linkspace::Datum::Curval' }
sub db_field_extra_export { [ qw/filter/ ] }
sub option_defaults { shift->SUPER::option_defaults(@_, @options) }
sub form_extras { [ qw/refers_to_sheet_id filter/ ], [ 'curval_columns' ] }

###
### Class
###

# _remove_column() by base-class

sub _validate($)
{   my ($thing, $update) = @_;
    $thing->SUPER::_validate($update);

    if(my $opt = $update->{options})
    {   $update->{is_multivalue} = exists $opt->{show_add} && $opt->{value_selector} eq 'noshow';
    }
}

###
### Instance
###

sub value_selector  { $_[0]->_options->{value_selector} // 'dropdown' }
sub show_add        { $_[0]->_options->{show_add} // 0 }
sub delete_not_used { $_[0]->_options->{delete_not_used} // 0 }

sub is_valid_value($)
{   my ($self, $value) = @_;

    my $row_id = is_valid_id $value
        or error __x"Value for {column} must be an row-id", column => $self->name;

    $self->curval_sheet->content->row($row_id)
        or error __x"Row-id {id} is not a valid row-id for {column.name_short}",
        id => $row_id, column => $self;

    $row_id;
}

# Whether this field has subbed in values from other parts of the record in its
# filter
sub has_subvals { $_[0]->filter->has_subvals }

# The fields that we need input by the user for this filtered set of values
sub subvals_input_required() { $_[0]->filter->subvals_input_required }

# The string/array that will be used in the edit page to specify the array of
# fields in a curval filter
sub data_filter_fields() { $_[0]->filter->data_filter_fields }

sub make_join
{   my ($self, @joins) = @_;
    @joins or return $self->field;

    +{ $self->field => { value => { record_single => [ 'record_later', @joins ] } } };
}

sub autocurs()
{   my $self = shift;
    my $document = $self->document;
    [ grep $_->type eq 'autocur', $document->columns_relating_to($self) ];
}

=pod

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

    my $page = $self->sheet_parent->content->search(
        limit_current_ids => [ map $_->{value}, @values ],
        is_draft          => $options{is_draft},
        columns           => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
    );

    # We need to retain the order of retrieved records, so that they are shown
    # in the correct order within each field. This order is defined with the
    # default sort for each table
    my %retrieved; my $order;
    while(my $row = $page->next_row)
    {   $retrieved{$row->current_id} = +{ record => $row, order  => ++$order }; # store order
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

#XXX move (at least partially) to ::Datum
#XXX move to Curcommon?
#XXX Unexpected side effects
sub field_values($$%)
{   my ($self, $datum, $row, %args) = @_;

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

    if($args{delete_not_used})
    {
        my @ids_deleted;
        foreach my $id_deleted (@{$datum->ids_removed})
        {
            my $is_used;
            foreach my $refers (@{$self->layout_parent->referred_by})
            {   my $refers_sheet = $refers->sheet_id;

                my $filter = { rule => {
                        column   => $refers,
                        type     => 'string',
                        operator => 'equal',
                        value    => $id_deleted,
                }};

                my $refers_page = $refers_sheet->content->search(
                    filter  => $filter,
                    columns => [],
                );

                $is_used = $refers_page->count;
                last if $is_used;
            }

            if(!$is_used)
            {   $self->sheet->content->current->row_delete($id_deleted);
                push @ids_deleted, $id_deleted;
            }
        }
        $datum->ids_deleted(\@ids_deleted);
    }

    map +{ value => $_ },
        @values ? @values : (undef);
}

sub does_refer_to_sheet($)
{   my ($self, $which) = @_;
    my $sheet_id = to_id $which;
    grep $_->child->sheet_id != $sheet_id, $self->curval_fields_parents;
}
=cut

1;
