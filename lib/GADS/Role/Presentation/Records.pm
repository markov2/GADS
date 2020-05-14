package GADS::Role::Presentation::Records;

use Moo::Role;

sub presentation($) {
    my $self  = shift;
    my $sheet = $self->sheet;

    my $view  = $self->view;
    my $current_group_id = $view ? $view->first_grouping_column_id : undef;

    my @show = map $_->presentation($sheet, group => $current_group_id, @_),
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

     +{
        columns => \@presentation,
      };
}

1;
