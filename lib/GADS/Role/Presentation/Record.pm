## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Role::Presentation::Record;

use Moo::Role;

use List::Util qw(first);

sub edit_columns
{   my ($self, %options) = @_;

    my %permissions
      = $options{approval} && $options{new} ? (user_can_approve_new => 1)
      : $options{approval} ? (user_can_approve_existing => 1)
      : $options{new}      ? (user_can_write_new => 1)
      :                      (user_can_readwrite_existing => 1);

    my @columns = $self->layout->columns_search(sort_by_topics => 1,
        can_child => $options{child}, userinput => 1, %permissions);

    @columns = grep $_->type ne 'file', @columns
        if $options{bulk} && $options{bulk} eq 'update';

    \@columns;
}

sub presentation(%) {
    my ($self, %options) = @_;

    # For an edit show all relevant fields for edit, otherwise assume record
    # read and show all view columns
    my @columns
        = $options{edit}          ? $self->edit_columns(%options)
        : $options{curval_fields} ? @{$options{curval_fields}}
        : $options{group}         ? @{$self->columns_view}
        : $options{purge}         ? $self->column('_id')
        :                           @{$self->columns_view};

    # Work out the indentation each field should have. A field will be indented
    # if it has a display condition of an immediately-previous field. This will
    # be recursive as long as there are additional display-dependent fields.
    my (%indent, %this_indent, $previous);
    foreach my $col (@columns)
    {
        if(my $df = $col->display_field)
        {   foreach my $display_field_id (@{$df->column_ids})
            {
                my $seen = $this_indent{$display_field_id} ? $display_field_id : undef;
                if($seen || ($previous && $display_field_id == $previous->id))
                {
                    $indent{$col->id} = $seen && $indent{$seen} ? ($indent{$seen} + 1) : 1;
                    $this_indent{$col->id} = $indent{$col->id};
                    last;
                }
                $indent{$col->id} = 0;
                %this_indent = ( $col->id => 0 );
            }
        }
        else
        {   $indent{$col->id} = 0;
            %this_indent = ( $col->id => 0 );
        }
        $previous = $col;
    }

    my $cur_id = $self->current_id;

    my @mapped  = map $_->presentation(datum_presentation =>
       $self->field($_->id)->presentation, %options), @columns;

    +{
        parent_id       => $self->parent_id,
        current_id      => $cur_id,
        record_id       => $self->record_id,
        instance_id     => $sheet->id,
        columns         => \@mapped,
        indent          => \%indent,
        deleted         => $self->deleted,
        deletedby       => $self->deletedby,
        createdby       => $self->createdby,
        user_can_delete => ($cur_id && $sheet->user_can('delete')),
        user_can_edit   => $sheet->user_can('write_existing'),
        id_count        => $self->id_count,
     };
}

1;
