package GADS::Role::Presentation::Datum::Curcommon;

use Moo::Role;

sub _presentation_details {
    my $self = shift;

    #return [] unless $self->as_string;

    my @links = map +{
        id                    => $_->{id},
        href                  => $_->{value},
        refers_to_instance_id => $self->column->related_sheet_id,
        values                => $_->{values},
        presentation          => $_->{record}->presentation($sheet, curval_fields => $self->column->curval_fields),
    }, @{$self->values};

    \@links;
}

sub presentation {
    my $self = shift;

    my $multivalue = $self->column->multivalue;   #XXX ???

    my $base = $self->presentation_base;
    $base->{text}  = $base->{value};
    $base->{links} = $self->_presentation_details;
    $base;
}

1;
