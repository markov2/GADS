package GADS::Role::Presentation::Column::Rag;

use Moo::Role;
use JSON qw(encode_json);

sub after_presentation
{   my ($self, $return) = @_;

    # Filter values normally only contains selected filters. For a RAG, because
    # there are only a few fixed options, we show them all regardless
    my $existing = decode_json($return->{filter_values});
    my %existing = map { $_->{id} => 1 } @$existing;

    my @selector = map +{
        id      => $_->[0],
        value   => $_->[1],
        checked => $exists{$_->{id}},
    }, $self->_filter_values;

    $return->{has_filter_search} = 0;
    $return->{filter_values} = encode_json \@filter_values;
    $return;
}

1;

