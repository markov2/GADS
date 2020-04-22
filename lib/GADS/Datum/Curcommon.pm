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

package GADS::Datum::Curcommon;

use Log::Report 'linkspace';
use CGI::Deurl::XS 'parse_query_string';
use HTML::Entities  qw/encode_entities/;
use Scalar::Util    qw/blessed/;
use List::Util      qw/uniq/;

use Linkspace::Util qw/list_diff is_valid_id/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Datum';

with 'GADS::Role::Presentation::Datum::Curcommon';

after set_value => sub {
    my ($self, $value, %options) = @_;

    # Ensure we don't accidentally set an autocur
    panic "Records passed to autocur set_value"
        if $self->column->type eq 'autocur' && !$options{allow_set_autocur};

    my $clone   = $self->clone; # Copy before changing text

    my (@records, @ids, @queries);
    foreach my $value (grep $_, ref $value eq 'ARRAY' ? @$value : $value)
    {   my $q = blessed $value && $value->isa('GADS::Record') ? \@records
              : is_valid_id($value) ? \@ids
              : \@queries;
        push @$q, $value;
    }

    @ids = sort @ids;  #XXX needed?
    my @old_ids = sort @{$self->ids};

    panic "Records cannot be mixed with other set values"
        if @records && (@ids || @queries);

    my $changed;
    $self->clear_values_as_records;

    if(@records)
    {   $self->_set_values_as_records(\@records);
        @ids = map $_->current_id, grep !$_->is_new_entry, @records;
        # Exclude the parent curval to prevent recursive loops
        my @queries = map $_->as_query(exclude_curcommon => 1),
            grep $_->is_new_entry, @records;

        $self->_set_values_as_query(\@queries);
        $self->clear_values_as_query_records; # Rebuild for new queries
    }

    if (@queries)
    {
        $self->_set_values_as_query(\@queries);
        $self->clear_values_as_query_records; # Rebuild for new queries
        $changed = 1 if grep { $_->is_edited } @{$self->values_as_query_records};
        # Remove any updated records from the list of old IDs in order to see
        # what has changed
        my %updated = map +($_->current_id => 1),
            grep !$_->is_new_entry, @{$self->values_as_query_records};
        @old_ids = grep !$updated{$_}, @old_ids;
    }

    $changed ||= "@ids" ne "@old_ids"; #  Also see if IDs have changed

    if ($changed)
    {
        $self->changed(1);
        $self->column->validate($_, fatal => 1)
            foreach @ids;
        # Need to clear initial values, to ensure new value is built from this new ID
        $self->clear_values;
        $self->clear_text;
        $self->clear_init_value;
        $self->_clear_init_value_hash;
        $self->_clear_records;
        $self->clear_already_seen_code;
        $self->clear_already_seen_level;
    }

    # Even if nothing has changed, we still need to set ids. This is because
    # the set values may have included unchanged records as queries. In this
    # case, the unchaged records will still be written as records
    # (values_as_query_records) even though they have not changed, so we don't
    # to also write the same IDs as values which will duplicate them.
    $self->_set_ids(\@ids);
    $self->oldvalue($clone);
};

# Hash with various values built from init_value. Used to populate
# specific value properties
has _init_value_hash => (
    is      => 'lazy',
    isa     => HashRef,
);

sub _build__init_value_hash
{   my $self = shift;
    if ($self->has_init_value) # May have been cleared after write
    {
        # initial value can either include whole record or just be ID. Assume
        # that they will be all one or the other
        my (@ids, @records);
        foreach my $v (@{$self->init_value})
        {
            my ($record, $id) = $self->_transform_value($v);
            push @records, $record if $record;
            # Don't include IDs of draft records. These will be recreated
            # afresh as required from the equivalent query string. Trying to
            # keep the same record from draft to main is too messy - things
            # like code values are not written, and removing the draft status
            # is fraught with danger.
            push @ids, $id if $id && (!$record || !$record->is_draft);
        }
        my $ret = {};
        $ret->{records} = \@records if @records;
        $ret->{ids}     = \@ids if @ids;
        return $ret;
    }
    elsif ($self->column->type eq 'autocur' && !$self->values_as_records) # Would be nice to abstract to autocur class
    {
        my @values = $self->column->fetch_multivalues([$self->record->record_id]);
        @values = map { $_->{value} } @values;
        +{
            ids     => [ map { $_->current_id } @values ],
            records => \@values,
        };
    }
    else {
        +{};
    }
}

has values => (
    is        => 'lazy',
    predicate => 1,
);

sub _build_values
{   my $self = shift;
    my $column = $self->column;

    if(my $r = $self->_init_value_hash->{records})
    {   return [ map $column->_format_row($_), @$r ];
    }

    my @return;
    if(my $r = $self->values_as_records)
    {
        foreach my $rec (@$r)
        {   my $values = $column->_format_row($rec)->{values};
            push @return, +{
                id       => !$rec->new_entry && $rec->current_id,
                as_query => $rec->new_entry && $rec->as_query,
                values   => $values,
                value    => $column->format_value(@$values),
                record   => $rec,
            };
        }
    }
    elsif( ! $self->is_blank )
    {   @return = $column->ids_to_values($self->ids, fatal => 1);

        my @records = @{$self->values_as_query_records};
        foreach my $query (@{$self->values_as_query})
        {   my $record = shift @records;
            my $values = $column->_format_row($record)->{values};
            push @return, +{
                id       => $record->current_id,
                as_query => $query,
                values   => $values,
                value    => $column->format_value(@$values),
                record   => $record,
            };
        }
    }
    \@return;
}

sub text_all { [ map $_->{value},  @{$_[0]->values} ] }
sub text     { join '; ', @{$_[0]->text_all} }
sub _records { [ map $_->{record}, @{$_[0]->values} ] }

sub is_blank
{   my $self = shift;
    @{$self->ids} || @{$self->values_as_query} ? 0 : 1;
}


has id_hash => (
    is      => 'lazy',
    builder => sub { +{ map +($_ => 1), @{$_[0]->ids} } },
}

has ids => (
    is      => 'lazy',
    builder => sub { $_[0]->_init_value_hash->{ids} || [] },
);

has ids_removed => (
    is  => 'lazy',
    isa => ArrayRef,
);

# The IDs of any records removed from this field's value
sub _build_ids_removed
{   my $self = shift;
    return [] if !$self->changed;

    my %old = map +($_ => 1), @{$self->oldvalue->ids};
    delete $old{$_} for @{$self->ids};
    delete $old{$_->current_id}
        for grep !$_->new_entry, @{$self->values_as_query_records};

    [ keys %old ];
}

# IDs of any records that have been removed and automatically deleted. This is
# calculated and set when writing the record.
has ids_deleted => (
    is      => 'rw',
    isa     => ArrayRef,
    default => sub { [] },
);

# All relevant ids (old and new)
sub ids_affected 
{  my $self = shift;
   my $old_ids = $self->oldvalue ? $self->oldvalue->ids : [];
   [ uniq @$old_ids, @{$self->ids} ];
}

sub ids_changed
{   my $self = shift;
    my $old_ids = $self->oldvalue ? $self->oldvalue->ids : [];
    my ($added, $deleted) = list_diff $old_ids, $self->ids;
    [ @$added, @$deleted ];
}

sub id
{   my $self = shift;
    $self->column->is_multivalue
        and panic "Cannot return single id value for multivalue field";
    $self->ids->[0];
}

# Remove any draft subrecords that have been created just for this curval
# field. These will be removed when the main draft is removed.
sub purge_drafts
{   my $self = shift;
    $_->delete_current, $_->purge_current foreach grep { $_->is_draft } @{$self->_records};
}

# Values as a URI query string. These are values submitted as queries via the
# curval-edit functionality. They will either be existing records edited or new
# records
has values_as_query => (
    is      => 'rwp',
    isa     => ArrayRef,
    default => sub { [] },
);

# The above values as queries, converted to records
has values_as_query_records => (
    is      => 'lazy',
    isa     => ArrayRef,
    clearer => 1,
);

sub _build_values_as_query_records
{   my $self = shift;
    my @records;
    foreach my $query (@{$self->values_as_query})
    {
        my $params = parse_query_string($query);
        grep { $_ !~ /^(?:csrf_token|current_id|field[0-9]+)$/ } keys %$params
            # Unlikely to be a user error
            and panic __x"Invalid query string: {query}", query => $query;
        my $record = GADS::Record->new(
            user   => $self->column->layout->user,
            layout => $self->column->layout_parent,
            schema => $self->column->schema,
        );
        if (my $current_id = $params->{current_id})
        {
            $record->find_current_id($current_id, include_draft => 1);
        }
        else {
            $record->initialise;
        }
        foreach my $col ($self->column->layout_parent->all(user_can_write_new => 1, userinput => 1))
        {
            my $newv = $params->{$col->field};
            # I can't find anything in official Jquery documentation, but
            # apparently form.serialize (the source of the query string)
            # encodes in utf-8. Therefore decode before passing into datums.
            my @newv = ref $newv eq 'ARRAY' ? @$newv : ($newv);
            $_ && utf8::decode($_) foreach @newv;
            $record->fields->{$col->id}->set_value(\@newv)
                if defined $params->{$col->field} && $col->userinput && defined $newv;
        }
        # Update any autocur fields with this record, so that the value can be
        # used immediately, without having to first write this record
        foreach my $col ($self->column->layout_parent->all)
        {
            next unless $col->type eq 'autocur';
            my $datum = $record->fields->{$col->id};
            my @records = grep { $_->current_id != $self->record->current_id } map { $_->{record} } @{$datum->values};
            push @records, $self->record;
            $datum->set_value(\@records, allow_set_autocur => 1);
        }
        $record->set_blank_dependents; # XXX Move to write() once back/forward functionality rewritten?
        push @records, $record;
    }
    \@records;
}

has values_as_records => (
    is      => 'rwp',
    clearer => 1,
);

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    my %extra = @_;
    my $fresh = delete $extra{fresh}; # Whether to clone full fresh records
    my %params;
    # If this is a full record clone of a "noshow" curval field, then any
    # cloned values would be expected to be written as new independent records.
    # Therefore, for these, clone the records within the value
    if ($fresh && $self->column->value_selector eq 'noshow')
    {
        my @copied = map {
            $_->{record}->clone;
        } @{$self->values};
        $params{values_as_query} = [map { $_->as_query } @copied];
    }
    else {
        # ids is built when noshow is true
        $params{ids}        = $self->ids;
        $params{init_value} = $self->init_value if $self->has_init_value;
        $params{values}     = $self->values if $self->has_values;
    }
    $orig->($self, %params, %extra);
};

sub as_string
{   my $self = shift;
    $self->text // "";
}

sub as_integer
{   my $self = shift;
    $self->id // 0;
}

sub html_withlinks
{   my $self = shift;
    $self->as_string or return "";
    my @return;
    foreach my $v (@{$self->values})
    {   my $string = encode_entities $v->{value};
        my $link   = "/record/$v->{id}?oi=".$self->related_sheet_id;
        push @return, qq(<a href="$link">$string</a>);
    }
    join '; ', @return;
}

sub field_values
{   my $self = shift;
    my $values = $self->_records
      ? $self->column->field_values(rows => $self->_records)
      : $self->column->field_values(ids => $self->ids);

    [ values %$values ];
}

sub field_values_for_code
{   my ($self, %options) = @_;
    $self->_records
        ? $self->column->field_values_for_code(rows => $self->_records, %options)
        : $self->column->field_values_for_code(ids => $self->ids, %options);
}

sub set_values
{   my $self = shift;
    $self->column->value_selector eq 'noshow'
        ? [ map { $_->{id} } @{$self->html_form} ]
        : $self->html_form;
}

sub html_form
{   my $self = shift;
    return $self->ids
        unless $self->column->value_selector eq 'noshow';

    my $record = $val->{record};
    my @return;
    foreach my $val (@{$self->values})
    {
        if ($val->{record}->is_draft)
        {
            $val->{as_query} = $val->{record}->as_query;
        }
        # New entries may have a current ID from a failed database write, but
        # don't use
        delete $val->{id} if $record->new_entry || $record->is_draft;
        $val->{presentation} = $record->presentation($sheet, curval_fields => $self->column->curval_fields);
        push @return, $val;
    }
    return \@return;
}

sub _build_for_code
{   my ($self, %options) = @_;

    my $already_seen_code = $self->already_seen_code;
    # Get all field data in one chunk
    my $field_values = $self->field_values_for_code(already_seen_code => $already_seen_code, level => $self->already_seen_level);

    my @values = map {
        +{
            id           => int $_->{id}, # Ensure passed to Lua as number not string
            value        => $_->{value},
            field_values => $field_values->{$_->{id}},
        }
    } grep { $_->{id} } (@{$self->values}); # Values that have not been written will not have an ID

    $self->column->multivalue || @values > 1 ? \@values : $values[0];
}

1;
