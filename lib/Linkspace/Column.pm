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

package GADS::Column;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Log::Report   'linkspace';
use MIME::Base64  qw/encode_base64/;
use JSON          qw/decode_json encode_json/;
use List::Compare ();

use Linkspace::Column::Autocur;
use Linkspace::Column::Calc;
use Linkspace::Column::Createdby;
use Linkspace::Column::Createddate;
use Linkspace::Column::Curval;
use Linkspace::Column::Date;
use Linkspace::Column::Daterange;
use Linkspace::Column::Deletedby;
use Linkspace::Column::Enum;
use Linkspace::Column::File;
use Linkspace::Column::Id;
use Linkspace::Column::Intgr;
use Linkspace::Column::Person;
use Linkspace::Column::Rag;
use Linkspace::Column::Serial;
use Linkspace::Column::String;
use Linkspace::Column::Tree;

#use namespace::clean; # Otherwise Enum clashes with MooseLike

with 'Linkspace::Role::Presentation::Column';

###
### META information about the column implementations.
#   These are class constants, very rarely flexible. It would be nicer
#   to make a ::Meta object, however: in that case the programmer must
#   be aware which methods are in meta...

my (%type2class, %class2type);

sub register_type(%)
{   my ($class, %args) = @_;
    my $type = $args{type} || lc(ref $class =~ s/.*::///r);
    $type2class{$type}   = $class;
    $class2type{$class}  = $type;
}

sub type2class($)  { $type2class{$_[1]} }
sub types()        { [ keys %type2class ] }
sub all_column_classes() { [ values %type2class ] }
sub type()         { $class2type{ref $_[0] || $_[0]} }

sub attributes_for($)
{   my ($thing, $type) = @_;
    my $class = $type2class{$type} or panic;
    @generic_attributes, @{$class->option_names};
}

#XXX some of these should have been named is_*()
sub addable        { 0 }   # support sensible addition/subtraction
sub can_multivalue { 0 }   #XXX same as multivalue?
sub fixedvals      { 0 }
sub has_cache      { 0 }   #XXX autodetect with $obj->can(write_cache)?
sub has_filter_typeahead { 0 } # has typeahead when inputting filter values
sub has_multivalue_plus  { 0 }
sub hidden         { 0 }   #XXX?
sub internal       { 0 }
sub is_curcommon   { $_[0]->isa('Linkspace::Column::Curcommon') }
sub meta_tables    { [ qw/String Date Daterange Intgr Enum Curval File Person/ ] }
sub multivalue     { 0 }
sub numeric        { 0 }
sub option_names   { shift; [ @_ ] };
sub retrieve_fields{ [ $_[0]->value_field ] }
sub return_type    { 'string' }
sub sort_field()   { $_[0]->value_field }
sub userinput      { 1 }
sub value_field    { 'value' }
sub value_to_write { 1 }   #XXX only in Autocur, may be removed
sub variable_join  { 0 }   # joins can be different on the config

# Whether the sort columns when added should be added with a parent, and
# if so what is the parent.  Default no, undef in case used in arrays.
sub sort_parent   { undef }

###
### Class
###

sub column_create(%)
{   my ($class, $insert) = @_;
    $self->type2class($insert->{type})->_column_create($insert);
}

sub _column_create($)
{   my ($class, $insert) = @_;

    $insert{related_field} = $insert{related_field}->id
        if blessed $insert{related_field};

    $self->create($insert)->id;
}

###
### Instance
###

sub sprefix        { $_[0]->field }
sub tjoin          { $_[0]->field }
sub filter_value_to_text { $_[1] }
sub value_field_as_index { $_[0]->value_field }

# Used when searching for a value's index value as opposed to
# string value (e.g. enums)
sub sort_columns   { [ $_[0] ] }

# Whether the data is stored as a string. If so, we need to check for both
# empty string and null values to test if empty
sub string_storage { 0 }

### helpers
sub site           { $::session->site }
sub returns_date   { $_[0]->return_type =~ /date/ }   #XXX ^date ?
sub field          { "field".($_[0]->id) }

# usage may avoid instantiation of a full sheet
# Please try to avoid the name 'instance_id' unless doing direct db access
sub sheet_id       { $_[0]->instance_id }

has sheet  => (
    is       => 'lazy',
    weakref  => 1,
    builder  => sub
    {   # dangling column needs it's sheet
        $_[0]->site->sheet($_[0]->instance_id);
    }
);

has layout => (
    is       => 'lazy',
    weakref  => 1,
    builder  => sub { $_[0]->sheet->layout },
);

# $self->valide($value)
sub validate   { 1 }   

has set_values => (
    is      => 'rw',
    trigger => sub { shift->build_values(@_) },
);

has id => (
    is  => 'rw',
    isa => Int,
);

has name => (
    is  => 'rw',
    isa => Str,
);

has name_short => (
    is  => 'rw',
    isa => Maybe[Str],
);

sub name_long() { $_[0]->name . ' (' . $_[0]->sheet->name . ')' }

has ordering => (
    is  => 'rw',
    isa => Maybe[Str],
);

has position => (
    is  => 'rw',
    isa => Maybe[Int],
);

has remember => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    default => 0,
    coerce  => sub { $_[0] ? 1 : 0 },
);

has isunique => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    default => 0,
    coerce  => sub { $_[0] ? 1 : 0 },
);

has can_child => (
    is      => 'lazy',
    isa     => Bool,
    coerce  => sub { $_[0] ? 1 : 0 },
);

sub _build_can_child
{   my $self = shift;
    if (!$self->userinput)
    {
        # Code values always have their own child values if the record is a
        # child, so that we build based on the true values of the child record.
        # Therefore return true if this is a code value which depends on a
        # child column
        return 1 if $::db->search(LayoutDepend => {
            layout_id => $self->id,
            'depend_on.can_child' => 1,
        },{
            join => 'depend_on',
        })->next;
    }
    $self->set_can_child;
}

has filter => (
    is      => 'lazy',
    builder => sub { GADS::Filter->new },
);

has display_condition => (
    is   => 'rw',
    lazy => 1,
    isa  => sub {
        my $val = shift;
        return if !$val || $val =~ /^(AND|OR)$/;
        panic "Unknown display_condition: $val";
    },
    coerce => sub { return undef if !$_[0]; $_[0] =~ s/\h+$//r },
);

has set_display_fields => (
    is        => 'rw',
    predicate => 1,
);

has display_fields => (
    is      => 'rw',
    lazy    => 1,
    coerce  => sub {
        my $val = shift;
        ref $val eq 'GADS::Filter' ? $val : GADS::Filter->new(as_json => $val);
    },
    builder => sub {
        my $self = shift;
        my @rules;
        if ($self->has_set_display_fields)
        {
            @rules = map +{
                id       => $_->{display_field_id},
                operator => $_->{operator},
                value    => $_->{regex},
            }, @{$self->set_display_fields};
        }
        else
        {   foreach my $cond ($::db->search(DisplayField =>{ layout_id => $self->id})->all)
            {
                push @rules, {
                    id       => $cond->display_field_id,
                    operator => $cond->operator,
                    value    => $cond->regex,
                };
            }
        }
        my $as_hash = !@rules ? {} : {
            condition => $self->display_condition || 'AND',
            rules     => \@rules,
        };
        return GADS::Filter->new(
            layout  => $self->layout,
            as_hash => $as_hash,
        );
    },
);

sub display_fields_as_text
{   my $self = shift;
    my $df = $self->display_fields_summary
        or return '';
    join ': ', @$df;
}

sub display_fields_summary
{   my $self = shift;
    if (my @display = $::db->search(DisplayField => { layout_id => $self->id })->all)
    {
        my $conds = join '; ', map { $_->display_field->name." ".$_->operator." ".$_->regex } @display;
        my $type = $self->display_condition eq 'AND'
            ? 'Only displayed when all the following are true'
            : $self->display_condition eq 'OR'
            ? 'Only displayed when any of the following are true'
            : 'Only display when the following is true';
        return [$type, $conds];
    }
}

has optional => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    default => 1,
    coerce  => sub { $_[0] ? 1 : 0 },
);

has description => (
    is  => 'rw',
    isa => Maybe[Str],
);

has width => (
    is  => 'rw',
    isa => Int,
);

has widthcols => (
    is => 'lazy',
);

sub _build_widthcols
{   my $self = shift;
    my $multiplus = $self->multivalue && $self->has_multivalue_plus;
    if ($self->layout->max_width == 100 && $self->width == 50)
    {
        return $multiplus ? 4 : 6;
    }
    else {
        return $multiplus ? 10 : 12;
    }
}

sub topic { $_[0]->sheet->topic($_[0]->topic_id) }

has aggregate => (
    is  => 'rw',
    isa => Maybe[Str],
);

has set_group_display => (
    is => 'rw',
);

has group_display => (
    is      => 'rw',
    isa     => Maybe[Str],
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->numeric ? 'sum' : $self->set_group_display;
    },
);

### display_field

has has_display_field => (
    is  => 'lazy',
    builder => sub { !! @{$self->display_fields->filters} },
)

has display_field_col_ids => (
    is      => 'lazy',
    builder => sub { [ map $_->column_id, @{$_[0]->display_fields->filters} ] },
);

sub display_fields_b64
{   my $self = shift;
    $self->has_display_field or return;
    encode_base64 $self->display_fields->as_json, ''; # base64 plugin does not like new lines in content
}

has link_parent => (
    is     => 'rw',
);

has link_parent_id => (
    is     => 'rw',
    isa    => Maybe[Int],
    coerce => sub { $_[0] || undef }, # String from form submit
);

sub suffix($)
{   my $self = shift;
      $self->return_type eq 'date' || $self->return_type eq 'daterange'
    ? '(\.from|\.to|\.value)?(\.year|\.month|\.day)?'
    : $self->type eq 'tree' ? '(\.level[0-9]+)?' : '';
);

# Used to provide a blank template for row insertion (to blank existing
# values). Only used in calc at time of writing
has blank_row => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { +{ $_[0]->value_field => undef } },
);

=head2 my $class = $column->datum_class;
=cut

sub datum_class() { ref $_[0] =~ s/^Linkspace::Column/Linkspace::Datum/r }

# Which fields this column depends on
has depends_on_ids => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub {
        my $self = shift;
        return [] if $self->userinput;

        my $depends = $::db->search(LayoutDepend => { layout_id => $self->id });
        [ $depends->get_column('depends_on')->all ];
    },
);

sub dependencies
{   my $self = shift;
    $self->has_display_field ? $self->display_field_col_ids : $self->depends_on_ids;
}

# Which columns depend on this field
has depended_by => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $depend = $::db->search(LayoutDepend => { depends_on => $self->id });
        [ map $_->get_column('layout_id'), $depend->all ];
    },
);

has dateformat => (
    is      => 'rw',
    isa     => Str,
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->layout->config->dateformat;
    },
);

sub parse_date
{   my ($self, $value) = @_;
    return if ref $value;

    # Check whether it's a CURDATE first
    my $dt = GADS::Filter->parse_date_filter($value);
    return $dt if $dt;

    $::session->user->local2dt($value);
}

sub permissions_by_group_export()
{   my $self = shift;
    my %permissions;
    push @{$permissions{$_->group_id}}, $_->permission
        for $self->_access_groups;

    \%permissions;
}


sub group_can
{   my ($self, $which, $perm) = @_;
    my $group_id = blessed $which ? $which->id : $which;
    my $perms = $self->permissions->{$group_id} || [];
    first { $_->short eq $perm } @$perms;
}

sub group_summary
{   my $self = shift;

    my %perms;
    foreach my $perm ($self->_access_groups)
    {   my $p = GADS::Type::Permission->new(short => $perm->permission);
        push @{$groups{$perm->group->name}}, $p->medium;
    }

    local $" = ', ';
    join "\n", map qq(Group "$_" has permissions: @{$groups{$_}}\n),
        sort keys %groups;
}

#-------------------
=head2 $column->column_update(%)
=cut

sub column_update($%)
{   my ($self, $update, %options) = @_;
    my $report = $args{report_only};

    notice __x"Update: related_field_id from {old} to {new}", 
        old => $self->related_field, new => $new_id
        if $report && $self->related_field != $new_id;

    delete $update{topic_id} unless $update{topic_id};

    my $link_parent = $original->{link_parent};
    if (ref $link_parent)
    {
        my $class = "GADS::Column::".camelize $link_parent->{type};
        my $column = $class->new(set_values => $link_parent);
        $self->link_parent($column);
    }
    else
    {   $self->link_parent_id($original->{link_parent});
    }

    $update{multivalue} ||= 0 if $update{multivalue};

    my $options = $original->{options} ? decode_json($original->{options}) : {};
    $self->_set_options($options);

    # XXX Move to curval class
    if ($self->type eq 'curval')
    {
        $self->set_filter($original->{filter});
        $self->multivalue(1) if $self->show_add && $self->value_selector eq 'noshow';
    }

}

#-----------------------
=head1 METHODS: Filters
=cut

# ID for the filter
has filter_id => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->id },
);

# Name of the column for the filter
has filter_name => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->name },
);

# Generic subroutine to fetch all multivalues for a table. Designed to satisfy
# most standard tables. Overridden for anything complicated.
sub fetch_multivalues
{   my ($self, $record_ids) = @_;

    my %select = (
        join       => 'layout',
        # Order by values so that multiple values appear in consistent order as
        # field values
        order_by   => "me.".$self->value_field,
        result_set => 'HASH',
    );

    if (ref $self->tjoin)
    {
        my ($left, $prefetch) = %{$self->tjoin}; # Prefetch table is 2nd part of join
        $select{prefetch} = $prefetch;
        # Override previous setting
        $select{order_by} = "$prefetch.".$self->value_field;
    }

    $::db->search($self->table => {
        'me.record_id'      => $record_ids,
        'layout.multivalue' => 1,
    }, \%select)->all;
}

=head2 my $filter = $column->filter_rules;
Inconvient name-collision with the table field, which should have been named
'filter_json'.
=cut

sub filter_rules(;$)
{   my $self = shift;
    @_==1 or return Linkspace::Filter->from_json($self->filter,
        layout => $self->layout);

    # Via filter object, to ensure validation
    my $set    = shift;
    my $filter = blessed $set && $set->isa('Linkspace::Filter') ? $set
      : Linkspace::Filter->from_json($set);

    my $json   = $filter->json;
    $self->update({filter => $json});
    $self->filter($json);
    $filter;
}

=head2 my $filter = $column->filter_remove_column($column);
=cut

sub filter_remove_column($)
{   my ($self, $column) = @_;
    $self->filter_rules($self->filter_rules->remove_column($column));
}

=head2 $column->remove_history;
Clean up any specialist data for all column types. The column's type may have
changed during its life, but the data may not have been removed on changed,
so we have to check all classes.
=cut

sub remove_history()
{   my $self = shift;
    $_->remove($self) for ${$self->all_column_classes};
}

sub write
{   my ($self, %options) = @_;

    error __"You do not have permission to manage fields"
        unless $self->layout->user_can("layout") || $options{override_permissions}; # For tests

    error __"Internal fields cannot be edited"
        if $self->internal;

    my $guard = $::db->begin_work;

    my $newitem;
    $newitem->{name} = $self->name
        or error __"Please enter a name for item";

    $newitem->{type} = $self->type
        or error __"Please select a type for the item";

    if ($newitem->{name_short} = $self->name_short)
    {
        # Check format
        $self->name_short =~ /^[a-z][_0-9a-z]*$/i
            or error __"Short names must begin with a letter and can only contain letters, numbers and underscores";
        # Check short name is unique
        my $search = {
            'me.name_short'    => $self->name_short,
            'instance.site_id' => $site->id,
        };

        if ($self->id)
        {   # Don't search self if already in DB
            $search->{'me.id'} = { '!=' => $self->id };
        }

        my $exists = $::db->get_record(Layout => $search, { join => 'instance' });
        $exists and error __x"Short name {short} must be unique but already exists for field \"{name}\"",
            short => $self->name_short, name => $exists->name;
    }

    # Check whether the parent linked field goes to a layout that has a curval
    # back to the current layout
    if ($self->link_parent_id)
    {
        my $link_parent = $::db->get_record(Layout => $self->link_parent_id);
        if ($link_parent->type eq 'curval')
        {
            foreach ($link_parent->curval_fields_parents)
            {
                error __x qq(Cannot link to column "{col}" which contains columns from this table),
                    col => $link_parent->name
                    if $_->child->instance_id == $self->instance_id;
            }
        }
    }

    $newitem->{topic_id}          = $self->topic_id;
    $newitem->{optional}          = $self->optional;
    $newitem->{remember}          = $self->remember;
    $newitem->{isunique}          = $self->isunique;
    $newitem->{can_child}         = $self->set_can_child if $self->has_set_can_child;
    $newitem->{filter}            = $self->filter->as_json;
    $newitem->{multivalue}        = $self->multivalue if $self->can_multivalue;
    $newitem->{description}       = $self->description;
    $newitem->{width}             = $self->width || 50;
    $newitem->{helptext}          = $self->helptext;
    $newitem->{options}           = encode_json($self->options);
    $newitem->{link_parent}       = $self->link_parent_id;
    $newitem->{display_condition} = $self->display_fields->as_hash->{condition},
    $newitem->{instance_id}       = $self->layout->instance_id;
    $newitem->{aggregate}         = $self->aggregate;

    $newitem->{group_display}
       = $self->numeric ? 'sum';
       : $self->group_display && $self->group_display eq 'unique' ? 'unique'
       : undef;

    $newitem->{position}          = $self->position
        if $self->position; # Used on layout import

    my ($new_id, $rset);

    unless ($options{report_only})
    {
        my $old_rset;
        if (!$self->id)
        {
            $newitem->{id} = $self->set_id if $self->set_id;
            # Add at end of other items
            $newitem->{position} = ($self->schema->resultset('Layout')->get_column('position')->max || 0) + 1
                unless $self->position;
            my $new_id = $self->create(Layout => $newitem);

            # Don't set $self->id here, as we could yet bail out and the object
            # would be left with an id, which would signify it is not a new field
            # (affects display of type when creating field)
        }
        elsif($rset = $::db->get_record(Layout => $self->id))
        {
            # Check whether attempt to move between instances - this is a bug
            $newitem->{instance_id} != $rset->instance_id
                and panic "Attempt to move column between instances";
            $old_rset = { $rset->get_columns };  #XXX pairs?
            $::db->update(Layout => $newitem);
        }
        else {
            $newitem->{id} = $self->id;
            $::db->create(Layout => $newitem);
        }

        # Write any column-specific params
        my %write_options = $self->write_special(rset => $rset, id => $new_id || $self->id, old_rset => $old_rset, %options);
        %options = (%options, %write_options);
    }

    $self->_write_permissions(id => $new_id || $self->id, %options);

    # Write display_fields
    my $display_rs = $::db->resultset('DisplayField');
    $display_rs->search({ layout_id => $self->id })->delete
        if $self->id;

    foreach my $cond (@{$self->display_fields->filters})
    {
        $cond->{column_id} == $self->id
            and error __"Display condition field cannot be the same as the field itself";
        $display_rs->create({
            layout_id        => $new_id || $self->id,
            display_field_id => $cond->{column_id},
            regex            => $cond->{value},
            operator         => $cond->{operator},
        });
    }

    $guard->commit;

    return if $options{report_only};

    if ($new_id || $options{add_db})
    {
        $self->id($new_id) if $new_id;
        unless ($options{no_db_add})
        {
            $self->schema->add_column($self);
            # Ensure new column is properly added to layout
            $self->layout->clear;
        }
    }
    $self->after_write_special(%options);

    $self->layout->clear_indexes;
}

sub user_can
{   my ($self, $permission) = @_;
    return 1 if  $self->internal  && $permission eq 'read';
    return 0 if !$self->userinput && $permission ne 'read'; # Can't write to code fields
    my $user = $::session->user;
    if($permission eq 'write') # shortcut
    {   return 1 $user->can_column($self, 'write_new')
              || $user->can_column($self, 'write_existing');
    }
    elsif($user->can_column($permission))
    {   return 1;
    }

    0;
}

# Whether a particular user ID has a permission for this column
sub user_id_can
{   my ($self, $user_id, $permission) = @_;
    return $self->layout->user_can_column($user_id, $self->id, $permission)
}

has set_permissions => (
    is        => 'rw',
    isa       => HashRef,
    predicate => 1,
);

sub _write_permissions
{   my ($self, %options) = @_;

    my $id = $options{id} || $self->id;

    $self->has_set_permissions or return;

    my %permissions = %{$self->set_permissions};

    my @groups = keys %permissions;

    # Search for any groups that were in the permissions but no longer exist.
    # Add these to the set_permissions hash, so they get processed and removed
    # as per other permissions (in particular ensuring the read_removed flag is
    # set)
    my $search = {
        layout_id => $id,
    };

    $search->{group_id} = { '!=' => [ '-and', @groups ] }
        if @groups;
        
    my @removed = $::db->search(LayoutGroup => $search,{
        select   => { max => 'group_id', -as => 'group_id' },
        as       => 'group_id',
        group_by => 'group_id',
    })->get_column('group_id')->all;

    $permissions{$_} = []
        foreach @removed;
    @groups = keys %permissions; # Refresh

    foreach my $group_id (@groups)
    {
        my @new_permissions = @{$permissions{$group_id}};

        my @existing_permissions = $::db->search(LayoutGroup =>{
            layout_id  => $id,
            group_id   => $group_id,
        })->get_column('permission')->all;

        my $lc = List::Compare->new(\@new_permissions, \@existing_permissions);

        my @removed_permissions = $lc->get_complement;
        my @added_permissions   = $lc->get_unique;

        # Has a read permission been removed from this group?
        my $read_removed = grep $_ eq 'read', @removed_permissions;

        # Delete any permissions no longer needed
        if ($options{report_only} && @removed_permissions)
        {
            notice __x"Removing the following permissions from {column} for group ID {group}: {perms}",
                column => $self->name, group => $group_id, perms => join(', ', @removed_permissions);
        }
        else
        {   $::db->delete(LayoutGroup => {
                layout_id  => $id,
                group_id   => $group_id,
                permission => \@removed_permissions,
            });
        }

        # Add any new permissions
        if ($options{report_only} && @added_permissions)
        {
            notice __x"Adding the following permissions to {column} for group ID {group}: {perms}",
                column => $self->name, group => $group_id, perms => \@added_permissions;
        }
        else
        {   $::db->create(LayoutGroup => {
                layout_id  => $id,
                group_id   => $group_id,
                permission => $_,
            }) foreach @added_permissions;
        }

        if ($read_removed && !$options{report_only}) {
            # First the sorts
            my @sorts = $::db->search(Sort => {
                layout_id      => $id,
                'view.user_id' => { '!=' => undef },
            }, {
                prefetch => 'view',
            })->all;

            foreach my $sort (@sorts) {
                # For each sort on this column, which no longer has read.
                # See if user attached to this view still has access with
                # another group
                $sort->delete unless $self->user_id_can($sort->view->user_id, 'read');
            }

            # Then the filters
            my @filters = $::db->search(Filter => {
                layout_id      => $id,
                'view.user_id' => { '!=' => undef },
            }, {
                prefetch => 'view',
            })->all;

            foreach my $filter (@filters) {
                # For each sort on this column, which no longer has read.
                # See if user attached to this view still has access with
                # another group

                next if $self->user_id_can($filter->view->user_id, 'read');

                # Filter cache
                $filter->delete;

                # Alert cache
                $::db->delete(AlertCache => {
                    layout_id => $id,
                    view_id   => $filter->view_id,
                });

                # Column in the view
                $::db->delete(ViewLayout => {
                    layout_id => $id,
                    view_id   => $filter->view_id,
                });

                # And the JSON filter itself
                my $view = $filter->view; #XXX
                $view->filter_remove_column($column);
				my $filtered = _filter_remove_colid($self, $filter->view->filter);

				$filter->view->update({ filter => $filtered });
            }
        }
    }
}

sub _filter_remove_colid
{   my ($self, $json) = @_;
    my $filter_dec = decode_json $json;
    _filter_remove_colid_decoded($filter_dec, $self->id);
    # An AND with empty rules causes JSON filter to have JS error
    $filter_dec = {} if !$filter_dec->{rules} || !@{$filter_dec->{rules}};
    encode_json $filter_dec;
}

# Recursively find all tables in a nested filter
sub _filter_remove_colid_decoded
{   my ($filter, $colid) = @_;

    if (my $rules = $filter->{rules})
    {
        # Filter has other nested filters
        @$rules = grep { _filter_remove_colid_decoded($_, $colid) && (!$_->{rules} || @{$_->{rules}}) } @$rules;
    }
    $filter->{id} && $colid == $filter->{id} ? 0 : 1;
}

sub validate_search
{   shift->validate(@_);
}

# Default sub returning nothing, for columns where a "like" search is not
# possible (e.g. integer)
sub resultset_for_values {};

sub values_beginning_with
{   my ($self, $match_string, %options) = @_;

    my $resultset = $self->resultset_for_values;
    my @value;
    my $value_field = 'me.'.$self->value_field;

    $match_string =~ s/([_%])/\\$1/g;
    my $search = $match_string
        ? { $value_field => { -like => "${match_string}%" } }
        : {};

    if ($resultset) {
        my $match_result = $resultset->search($search, { rows => 10 });
        if($options{with_id} && $self->fixedvals)
        {
            @value = map +{
               id   => $_->get_column('id'),
               name => $_->get_column($self->value_field),
            }, $match_result->search({}, {
                  columns => ['id', $value_field],
               })->all;
        }
        else {
        {   @value = $match_result->search({}, {
                select => { max => $value_field, -as => $value_field },
            })->get_column($value_field)->all;
        }
    }
    return @value;
}

# The regex that will match the column in a calc/rag code definition
sub code_regex
{   my $self   = shift;
    my $name   = $self->name;
    my $suffix = $self->suffix;
    qr/\[\^?\Q$name\E$suffix\Q]/i;
}

sub additional_pdf_export {}

sub import_hash
{   my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    my %update;

    # validate/normalize json
    $values->{filter} = Linkspace::Filter->from_json($values->{filter})->as_json;

    my $take   = sub {
        my $field = shift;
        my $new   = $values->{field};
        return if +($old // '') eq +($new // '');

        notice __x"Update: {field} from '{old}' to '{new}' for {name}",
            field => $field, old => $self->$field, new => $new, name => $name
            if $report;

        $update{$field} = $new;
    };

    $take->($_) for
        @simple_import_attributes,
        ${$self->option_names};
}

my @simple_import_attributes = 
   qw/name name_short optional remember isunique can_child position description
      aggregate width filter helptext multivalue group_display/;

my @simple_export_attributes =
   qw/id type topic_id display_condition/

sub export_hash
{   my $self = shift;

    my @display_fields = map +{           #XXX move to filter->export_hash()
        id       => $filter->{column_id},
        value    => $filter->{value},
        operator => $filter->{operator},
    }, @{$self->display_fields->filters};

    my %export = (
        display_fields    => \@display_fields,
        link_parent       => $self->link_parent && $self->link_parent->id,
        permissions       => $self->permissions_by_group_export,
        @_,                               # from extensions
    };

    $export{$_} = $self->$_ for
        @simple_import_attributes,
        @simple_export_attributes,
        @{$self->option_names};

    \%export;
}

# Subroutine to run after a column write has taken place for an import
sub import_after_write {};

# Subroutine to run after all columns have been imported
sub import_after_all
{   my ($self, $values, %options) = @_;
    my $mapping = $options{mapping};
    my $report  = $options{report_only};

    if (@{$values->{display_fields}})
    {
        my @rules;
        foreach my $filter (@{$values->{display_fields}})
        {
            $filter->{id} = $mapping->{$filter->{id}};
            push @rules, $filter;
        }
        $self->display_fields->as_hash({
            condition => $values->{display_condition} || 'AND',
            rules     => \@rules,
        });
    }
    else
    {   $self->display_fields->as_hash({});
    }

    notice __x"Update: display_fields has been updated for {name}",
        name => $self->name
            if $report && $self->display_fields->changed;

    my $new_id = $values->{link_parent} ? $mapping->{$values->{link_parent}} : undef;
    notice __x"Update: link_parent from {old} to {new} for {name}",
        old => $self->link_parent, new => $new_id, name => $self->name
            if $report && ($self->link_parent || 0) != ($new_id || 0);
    $self->link_parent($new_id);
}

=head2 $class->how_to_link_to_record($record);
Tricky part, during schema initiation where methods are produced for fields.
=cut

sub how_to_link_to_record
{   my ($class, $record) = @_;

    ( $class->table, sub {
       +{ "$_[0]->{foreign_alias}.record_id" => { -ident => "$_[0]->{self_alias}.id" },
          "$_[0]->{foreign_alias}.layout_id" => $record->id,
        };
      } );
}

=head2 my @entries = $column->field_values($datum, $row, %options);
Returns entries to be written to the database for $datum.
Fields C<child_unique> and C<layout_id> are added later.

The C<$row> and C<%options> are only used for Curval.
=cut

#XXX %options are used by Curval.  For which purpose?
#XXX For Curvals this has weird side effects
sub field_values($$%)
{   my ($self, $datum) = @_;

    my @values = $self->can('ids') ? $datum->ids : $datum->value;
    @values or @values = (undef);

    map +{ value => $_ }, @values;
}

### Only used by Autocur
#   XXX The 'related_field' contains the id, which makes it hard to give
#   XXX nice names to the methods.
sub related_column_id  { $_[0]->related_field }
sub related_column()   { $_[0]->layout->column($_[0]->related_field) }

sub related_sheet_id() {
    my $column = $_[0]->related_column;
    $column ? $column->sheet_id : undef;
}

1;

