package GADS::Role::Presentation::Datum;

use Moo::Role;

sub presentation { shift->presentation_base } # Default, overridden

sub presentation_base {
    my $self = shift;
    return {
        type            => $self->isa('GADS::Datum::Count') ? 'count' : $self->column->type,
        value           => $self->as_string,
        filter_value    => $self->filter_value,
        blank           => $self->blank,
        dependent_shown => $self->dependent_shown,
    };
}

1;
