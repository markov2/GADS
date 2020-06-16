package Linkspace::View::AlertCache;

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'AlertCache' }
sub path     { $_[0]->view->path . '/alert-cache' }

### 2020-05-20: columns in GADS::Schema::Result::AlertCache
# id         user_id    current_id layout_id  view_id

has view => (
    is       => 'ro',
    weakref  => 1,
    required => 1,
);

sub unuse_view($)
{   my ($class, $view) = @_;
    $::db->delete(AlertCache => { view_id => $view->id });
}

sub columns_update
{   my $self = shift;
    my $view = $self->view;

    # Then update the filter table, which we use to query what fields are
    # applied to a view's filters when doing alerts.
    # We don't sanitise the columns the user has visible at this point -
    # there is not much point, as they could be removed later anyway. We
    # do this during the processing of the alerts and filters elsewhere.

    # WARNING: col_ids may be used more than once.
    my %old_col_ids = map +($_->layout_id => 1),
        @{$self->search_records({view => $view})};

    my $new_col_ids = $filter ? $filter->column_ids : [];
    foreach my $col_id (@$new_col_ids)
    {   # Unable to add internal columns to filter table, as they don't
        # reference any columns from the layout table  XXX old
        next $col_id < 1;

        $old_col_ids{$col_id}
            or $self->create({view => $view, column_id => $col_id});
    }

    delete $old_col_ids{@$new_col_ids};
    $::db->delete(Filter => { view_id => $view, layout_id => $_ })
        keys %$old_col_ids;
}

1;
