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

use Log::Report 'linkspace';

use GADS::Groups;
use GADS::Type::Permission;
use GADS::View;

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

use MIME::Base64 /encode_base64/;
use JSON qw(decode_json encode_json);
use String::CamelCase qw(camelize);
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use List::Compare ();

use namespace::clean; # Otherwise Enum clashes with MooseLike

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
sub types()        { keys %type2class }
sub all_column_classes() { values %type2class }
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
### Instance
###

sub sprefix        { $_[0]->field }
sub tjoin          { $_[0]->field }
sub filter_value_to_text { $_[1] }
sub value_field_as_index { $_[0]->value_field }

# Cleanup specialist column data when a column is deleted
sub cleanup        {}

# Used when searching for a value's index value as opposed to
# string value (e.g. enums)
sub sort_columns   { $_[0] }

### helpers
sub site           { $::session->site }
sub returns_date   { $_[0]->return_type =~ /date/ }
sub field          { "field".($_[0]->id) }

# All permissions for this column
has permissions => (
    is  => 'lazy',
    isa => HashRef,
);

has from_id => (
    is      => 'rw',
    trigger => sub {
        my ($self, $col_id) = @_;
        # Column needs to be built from its sub-class, otherwise methods only
        # relavent to that type will not be available
        ref $self eq __PACKAGE__
            and panic "from_id cannot be called on raw GADS::Column object";

        my $col = $::db->search(Layout => {
            'me.id'          => $col_id,
            'me.instance_id' => $self->sheet->id,
        },{
            order_by => ['me.position', 'enumvals.id'],
            prefetch => [ qw/enumvals calcs rags file_options/ ],
            result_class => 'HASH',
        })->first;

        $col or error __x"Field ID {id} not found", id => $value;
        $self->set_values($col);
    },
);

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

has options => (
    is        => 'rwp',
    isa       => HashRef,
    lazy      => 1,
    builder   => 1,
    predicate => 1,
);

sub reset_options
{   my $self = shift;
    # Force each option to build now to capture its value, otherwise if it
    # hasn't already been built then the options hash will be lost and it will
    # use its default value
    $self->$_ foreach @{$self->option_names};
    $self->clear_options;
}

sub _build_options
{   my $self = shift;
    my $options = {};
    foreach my $option_name (@{$self->option_names})
    {   $options->{$option_name} = $self->$option_name;
    }
    $options;
}

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

has set_can_child => (
    is        => 'rw',
    isa       => Bool,
    predicate => 1,
    coerce    => sub { $_[0] ? 1 : 0 },
    trigger   => sub { shift->clear_can_child },
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
    return $self->set_can_child;
}

has filter => (
    is      => 'rw',
    lazy    => 1,
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
    clearer => 1,
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
        {   foreach my $cond ($::db->search(DisplayField =>{
                layout_id => $self->id
            })->all)
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

# Whether the data is stored as a string. If so, we need to check for both
# empty string and null values to test if empty
has string_storage => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    default => 0,
);

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

has topic_id => (
    is     => 'rw',
    isa    => Maybe[Int],
    coerce => sub { $_[0] || undef }, # Account for empty string from form
);

has topic => (
    is => 'lazy',
);

sub _build_topic
{   my $self = shift;
    $self->topic_id or return;
    $self->schema->resultset('Topic')->find($self->topic_id);
}

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

has has_display_field => (
    is  => 'lazy',
    isa => Bool,
);

sub _build_has_display_field
{   my $self = shift;
    !!@{$self->display_fields->filters};
}

has display_field_col_ids => (
    is      => 'lazy',
    builder => sub { [ map $_->column_id, @{$_[0]->display_fields->filters} ] },
);

sub display_fields_b64
{   my $self = shift;
    $self->has_display_field or return;
    encode_base64 $self->display_fields->as_json, ''; # base64 plugin does not like new lines in content
}

has helptext => (
    is  => 'rw',
    isa => Maybe[Str],
);

has link_parent => (
    is     => 'rw',
);

has link_parent_id => (
    is     => 'rw',
    isa    => Maybe[Int],
    coerce => sub { $_[0] || undef }, # String from form submit
);

has suffix => (
    is   => 'rw',
    isa  => Str,
    lazy => 1,
    builder => sub {
        $_[0]->return_type eq 'date' || $_[0]->return_type eq 'daterange'
        ? '(\.from|\.to|\.value)?(\.year|\.month|\.day)?'
        : $_[0]->type eq 'tree'
        ? '(\.level[0-9]+)?'
        : '';
    },
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
has depends_on => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub {
        my $self = shift;
        return [] if $self->userinput;
        my @depends = $::db->(LayoutDepend => { layout_id => $self->id })->all;
        [ map $_->get_column('depends_on'), @depends ];
    },
);

sub dependencies
{   my $self = shift;
    $self->has_display_field ? $self->display_field_col_ids : $self->depends_on;
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

sub _build_permissions
{   my $self = shift;
    my @all = $::db->search(LayoutGroup => layout_id => $self->id });
    my %perms;
    foreach my $p (@all)
    {
        $perms{$p->group_id} ||= [];
        push @{$perms{$p->group_id}}, GADS::Type::Permission->new(
            short => $p->permission
        );
    }
    \%perms;
}

sub group_has
{   my ($self, $group_id, $perm) = @_;
    my $perms = $self->permissions->{$group_id}
        or return 0;
    (grep { $_->short eq $perm } @$perms) ? 1 : 0;
}

# Return a human-readable summary of groups
sub group_summary
{   my $self = shift;

    my %groups;

    foreach my $perm ($self->schema->resultset('LayoutGroup')->search({ layout_id => $self->id })->all)
    {
        $groups{$perm->group->name} ||= [];
        my $p = GADS::Type::Permission->new(short => $perm->permission);
        push @{$groups{$perm->group->name}}, $p->medium;
    }

    my $return =  '';

    foreach my $group (keys %groups)
    {
        $return .= qq(Group "$group" has permissions: ).join(', ', @{$groups{$group}})."\n";
    }

    return $return;
}

sub _build_instance_id
{   my $self = shift;
    $self->layout
        or panic "layout is not set - specify instance_id on creation instead?";
    $self->layout->instance_id;
}

sub build_values
{   my ($self, $original) = @_;

    my $link_parent = $original->{link_parent};
    if (ref $link_parent)
    {
        my $class = "GADS::Column::".camelize $link_parent->{type};
        my $column = $class->new(set_values => $link_parent);
        $self->link_parent($column);
    }
    else {
        $self->link_parent_id($original->{link_parent});
    }
    $self->id($original->{id});
    $self->name($original->{name});
    $self->name_short($original->{name_short});
    $self->topic_id($original->{topic_id});
    $self->optional($original->{optional});
    $self->remember($original->{remember});
    $self->isunique($original->{isunique});
    $self->set_can_child($original->{can_child});
    $self->multivalue($original->{multivalue} ? 1 : 0) if $self->can_multivalue;
    $self->position($original->{position});
    $self->helptext($original->{helptext});
    my $options = $original->{options} ? decode_json($original->{options}) : {};
    $self->_set_options($options);
    $self->description($original->{description});
    $self->width($original->{width});
    $self->field("field$original->{id}");
    $self->type($original->{type});
    $self->display_condition($original->{display_condition});
    $self->set_display_fields($original->{display_fields});
    $self->set_group_display($original->{group_display});
    $self->aggregate($original->{aggregate} || undef);

    # XXX Move to curval class
    if ($self->type eq 'curval')
    {
        $self->set_filter($original->{filter});
        $self->multivalue(1) if $self->show_add && $self->value_selector eq 'noshow';
    }

}

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

sub column_delete
{   my $self = shift;

    my $guard = $::db->begin_work;

    # First see if any views are conditional on this field
    if(my @deps = $::db->search(DisplayField => { display_field_id => $self->id })->all)
    {
        my @names = map $_->layout->name, @deps;
        error __x"The following fields are conditional on this field: {dep}.
            Please remove these conditions before deletion.", dep => \@names;
    }

    # Next see if any calculated fields are dependent on this
    if(@{$self->depended_by})
    {   my @deps = map $self->layout->column($_)->name, @{$self->depended_by};
        error __x"The following fields contain this field in their formula: {dep}.
            Please remove these before deletion.", dep => \@deps;
    }

    # Now see if any Curval fields depend on this field
    if(my @parents = $::db->search(CurvalField => { child_id => $self->id })->all)
    {   my @pn = map $_->parent->name." (".$_->parent->instance->name.")", @parents;
        error __x"The following fields in another table refer to this field: {p}.
            Please remove these references before deletion of this field.", p => \@pn;
    }

    # Now see if any linked fields depend on this one
    if(my @linked = $::db->search(Layout => { link_parent => $self->id })->all)
    {   my @ln = map $_->name." (".$_->sheet->name.")", @linked;
        error __x"The following fields in another table are linked to this field: {l}.
            Please remove these links before deletion of this field.", l => \@ln;
    }

    if(my @graphs = $::db->search(Graph => [
                { x_axis   => $self->id },
                { y_axis   => $self->id },
                { group_by => $self->id },
            ]
        )->all)
    {
        error __x"The following graphs references this field: {graph}. Please update them before deletion."
            , graph => [ map $_->title, @graphs ]; 
    }

    # Remove this column from any filters defined on views
    foreach my $filter ($::db->search(Filter => { layout_id => $self->id })->all)
    {
        my $filtered = _filter_remove_colid($self, $filter->view->filter);
        $filter->view->update({ filter => $filtered });
    }

    # Same again for fields with filter
    foreach my $col ($::db->search(Layout => { filter => { '!=' => '{}' }})->all)
    {
        $col->filter or next;
        my $filtered = _filter_remove_colid($self, $col->filter);
        $col->update({ filter => $filtered });
    };

    # Clean up any specialist data for all column types. The column's
    # type may have changed during its life, but the data may not
    # have been removed on change, so we have to check all classes.
    foreach my $type (grep $_ ne 'serial', $self->types)
    {
        my $class = "GADS::Column::".camelize $type;
        $class->cleanup($self->id);
    }

    my %layout_ref = (layout_id => $self->id);
    $::db->delete($_ => \%layout_ref)
        qw/AlertCache AlertSend DisplayField Filter LayoutDepend
           LayoutGroup Sort ViewLayout/;

    $::db->delete(Sort => { parent_id => $self->id });
    $::db->update(Instance => { sort_layout_id => $self->id }, {sort_layout_id => undef});
    $::db->delete(Layout => $self->id);

    $guard->commit;
}

sub write_special { () } # Overridden in children
sub after_write_special {} # Overridden in children

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
    return 1 if $self->user_permission_override;
    return 1 if $self->internal && $permission eq 'read';
    return 0 if !$self->userinput && $permission ne 'read'; # Can't write to code fields
    return 1 if $self->layout->current_user_can_column($self->id, $permission);
    if ($permission eq 'write') # shortcut
    {
        return 1
            if $self->layout->current_user_can_column($self->id, 'write_new')
            || $self->layout->current_user_can_column($self->id, 'write_existing');
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
        
    my @removed = $self->schema->resultset('LayoutGroup')->search($search,{
        select   => {
            max => 'group_id',
            -as => 'group_id',
        },
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
            my @sorts = $self->schema->resultset('Sort')->search({
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

sub validate
{   my ($self, $value) = @_;
    1; # Overridden in child classes
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
{   my $self  = shift;
    my $name  = $self->name; my $suffix = $self->suffix;
    qr/\[\^?\Q$name\E$suffix\Q]/i;
}

sub additional_pdf_export {}

sub import_hash
{   my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    notice __x"Update: name from {old} to {new} for {name}",
        old => $self->name, new => $values->{name}, name => $self->name
            if $report && $self->name ne $values->{name};
    $self->name($values->{name});
    notice __x"Update: name_short from {old} to {new} for {name}",
        old => $self->name_short, new => $values->{name_short}, name => $self->name
            if $report && ($self->name_short || '') ne ($values->{name_short} || '');
    $self->name_short($values->{name_short});
    notice __x"Update: optional from {old} to {new} for {name}",
        old => $self->optional, new => $values->{optional}, name => $self->name
            if $report && $self->optional != $values->{optional};
    $self->optional($values->{optional});
    notice __x"Update: remember from {old} to {new} for {name}",
        old => $self->remember, new => $values->{remember}, name => $self->name
            if $report && $self->remember != $values->{remember};
    $self->remember($values->{remember});
    notice __x"Update: isunique from {old} to {new} for {name}",
        old => $self->isunique, new => $values->{isunique}, name => $self->name
            if $report && $self->isunique != $values->{isunique};
    $self->isunique($values->{isunique});
    notice __x"Update: can_child from {old} to {new} for {name}",
        old => $self->can_child, new => $values->{can_child}, name => $self->name
            if $report && $self->can_child != $values->{can_child};
    $self->set_can_child($values->{can_child});
    notice __x"Update: position from {old} to {new} for {name}",
        old => $self->position, new => $values->{position}, name => $self->name
            if $report && $self->position != $values->{position};
    $self->position($values->{position});
    notice __x"Update: description from {old} to {new} for {name}",
        old => $self->description, new => $values->{description}, name => $self->name
            if $report && $self->description ne $values->{description};
    $self->description($values->{description});
    notice __x"Update: aggregate from {old} to {new} for {name}",
        old => $self->aggregate, new => $values->{aggregate}, name => $self->name
            if $report && ($self->aggregate || '') ne ($values->{aggregate} || '');
    $self->aggregate($values->{aggregate});
    notice __x"Update: group_display from {old} to {new} for {name}",
        old => $self->group_display, new => $values->{group_display}, name => $self->name
            if $report && ($self->group_display || '') ne ($values->{group_display} || '');
    $self->group_display($values->{group_display});
    notice __x"Update: width from {old} to {new} for {name}",
        old => $self->width, new => $values->{width}, name => $self->name
            if $report && $self->width != $values->{width};
    $self->width($values->{width});
    notice __x"Update: helptext from {old} chars to {new} chars for {name}",
        old => length($self->helptext), new => length($values->{helptext}), name => $self->name
            if $report && $self->helptext ne $values->{helptext};
    $self->helptext($values->{helptext});
    notice __x"Update: multivalue from {old} to {new} for {name}",
        old => $self->multivalue, new => $values->{multivalue}, name => $self->name
            if $report && $self->multivalue != $values->{multivalue};
    $self->multivalue($values->{multivalue});

    $self->filter(GADS::Filter->new(as_json => $values->{filter}));
    notice __x"Update: filter from {old} to {new} for {name}",
        old => $self->filter->as_json, new => $values->{filter}, name => $self->name
            if $report && $self->filter->changed;
    foreach my $option (@{$self->option_names})
    {
        notice __x"Update: {option} from {old} to {new} for {name}",
            option => $option, old => $self->$option, new => $values->{$option}, name => $self->name
                if $report && $self->$option ne $values->{$option};
        $self->$option($values->{$option});
    }
}

sub export_hash
{   my $self = shift;
    my $permissions;
    foreach my $perm ($self->schema->resultset('LayoutGroup')->search({ layout_id => $self->id })->all)
    {
        $permissions->{$perm->group_id} ||= [];
        push @{$permissions->{$perm->group_id}}, $perm->permission;
    }
    my $return = {
        id                => $self->id,
        type              => $self->type,
        name              => $self->name,
        name_short        => $self->name_short,
        topic_id          => $self->topic_id,
        optional          => $self->optional,
        remember          => $self->remember,
        isunique          => $self->isunique,
        can_child         => $self->can_child,
        position          => $self->position,
        description       => $self->description,
        width             => $self->width,
        helptext          => $self->helptext,
        display_condition => $self->display_condition,
        link_parent       => $self->link_parent && $self->link_parent->id,
        multivalue        => $self->multivalue,
        filter            => $self->filter->as_json,
        aggregate         => $self->aggregate,
        group_display     => $self->group_display,
        permissions       => $permissions,
    };

    my @display_fields;
    foreach my $filter (@{$self->display_fields->filters})
    {
        push @display_fields, {
            id       => $filter->{column_id},
            value    => $filter->{value},
            operator => $filter->{operator},
        };
    }
    $return->{display_fields} = \@display_fields;
    foreach my $option (@{$self->option_names})
    {
        $return->{$option} = $self->$option;
    }
    return $return;
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
    else {
        $self->display_fields->as_hash({});
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

sub how_to_link_to_record {
    my ($self, $schema) = @_;

    my $linker = sub {
        my ($other, $me) = ($_[0]->{foreign_alias}, $_[0]->{self_alias});

        return {
            "$other.record_id" => { -ident => "$me.id" },
            "$other.layout_id" => $self->id,
        };
    };

    ($self->table, $linker);
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

1;

