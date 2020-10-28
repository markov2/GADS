## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::DBIC;

use base qw(DBIx::Class);

# Used as a component for result sources to perform additional DBIC functions
# (such as validation of values).  For validation, the Result needs a
# validate() function.  It should raise an exception if there is a problem.

sub insert
{   my $self = shift;
    $self->_validate(@_);
    $self->_before_create(@_);
    my $guard = $self->result_source->schema->txn_scope_guard;
    my $return = $self->next::method(@_);
    $self->after_create
        if $self->can('after_create');
    $guard->commit;
    $return;
}

sub delete
{   my $self = shift;
    $self->before_delete
        if $self->can('before_delete');
    $self->next::method(@_);
}

sub update 
{   my $self = shift;
    $self->_validate(@_);
    $self->next::method(@_);
}

sub _validate
{   my ($self, $values) = @_;
    # If update() has been called with a set of values, then these need to be
    # updated in the object first, otherwise validation will be done on the
    # existing values in the object not the new ones.
    if ($values)
    {
        $self->$_($values->{$_}) foreach keys %$values;
    }
    $self->validate
        if $self->can('validate');
};

sub _before_create
{   my $self = shift;
    $self->before_create
        if $self->can('before_create');
};


1;
