## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Role::Presentation::Column;

use Moo::Role;
use JSON qw(encode_json);
use URI::Escape qw/uri_escape_utf8/;

sub presentation {
    my ($self, %options) = @_;
    my $qp = $options{query_parameters};  #XXX handling should move to GADS.pm

    # data-values='[{"id": "23", "value": "Foo", "checked": true}, {"id": "24", "value": "Bar", "checked": true}]'

    my ($has_filter, @filter_values, $filter_text, @queries);
    foreach my $filter (@{$options{filters}})
    {
        if ($filter->{id} == $self->id)
        {
            $has_filter = 1;
            if($self->fixedvals)
            {   push @filter_values, map +{
                    id      => $_,
                    value   => $self->id_as_string($_),
                    checked => \1,
                }, @{$filter->{value}};
            }
            else
            {   $filter_text = $filter->{value}->[0];
            }
        }
        else
        {
            push @queries, "field$filter->{id}=".uri_escape_utf8($_)
                for @{$filter->{value}};
        }
    }

    foreach my $key (grep !/^field/, keys %$qp)
    {   push @queries, "$key=$_" for $qp->get_all($key);
    }

    my $url_filter_remove = join '&', @queries;

    my %val = (
        id                  => $self->id,
        type                => $self->type,
        name                => $self->name,
        is_id               => $self->name_short && $self->name_short eq '_id',
        topic               => $self->topic && $self->topic->name,
        topic_id            => $self->topic && $self->topic->id,
        is_multivalue       => $self->is_multivalue,
        helptext            => $self->helptext,
        readonly            => $options{new} ? !$self->user_can('write_new') : !$self->user_can('write_existing'),
        data                => $options{datum_presentation},
        is_group            => $options{group} && $options{group} == $self->id,
        has_filter          => $has_filter,
        url_filter_remove   => $url_filter_remove,
        filter_values       => encode_json \@filter_values,
        filter_text         => $filter_text,
        has_filter_search   => 1,
        fixedvals           => $self->fixedvals,
    );

    # XXX Reference to self when this is used within edit.tt. Ideally this
    # wouldn't be needed and all parameters that are needed would be passed as
    # above.
    $val{column} = $self
        if $options{edit};

    my $sorter;
    if (my $sort = $options{sort})
    {    $val{sort}
           = $sort->{id} != $self->id ? +{
                symbol  => '&darr;',
                text    => 'ascending',
                link    => $self->id.'asc',
             }
           : $sort->{type} eq 'asc'  ? +{
                symbol  => '&udarr;',
                text    => 'descending', # Text to change the sort
                current => '&darr;',
                link    => $self->id.'desc',
                aria    => 'ascending', # Current sort
             }
           : +{
                symbol  => '&udarr;',
                text    => 'ascending',
                current => '&uarr;',
                link    => $self->id.'asc',
                aria    => 'descending',
            };
    }

    $self->after_presentation(\%val, %options);
    \%val;
}

sub after_presentation {}; # Dummy, overridden

1;
