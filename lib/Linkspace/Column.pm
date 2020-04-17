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

package Linkspace::Column;

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

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table';

sub db_table { 'Layout' }
sub db_field_rename { +{
    display_field => 'display_field_json',
    display_regex => 'display_regex_string',
    internal      => 'is_internal',
    isunique      => 'is_unique',
    link_parent   => 'link_parent_id',
    multivalue    => 'is_multivalue',
    related_field => 'related_field_id',
#   permission    => ''   XXX???
    };
}
sub db_fields_unused { qw/filter/ }

### 2020-04-14: columns in GADS::Schema::Result::Layout
# id                display_field     internal          permission
# instance_id       display_matchtype isunique          position
# name              display_regex     link_parent       related_field
# type              end_node_only     multivalue        remember
# aggregate         filter            name_short        textbox
# can_child         force_regex       optional          topic_id
# description       group_display     options           typeahead
# display_condition helptext          ordering          width


use namespace::clean; # Otherwise Enum clashes with MooseLike

with 'Linkspace::Role::Presentation::Column';

###
### META information about the column implementations.
#   These are class constants, very rarely flexible. It would be nicer
#   to make a ::Meta object, however: in that case the programmer must
#   be aware which methods are in meta...

my %type2class;

sub register_type(%)
{   my ($class, %args) = @_;
    my $type = $args{type} || lc(ref $class =~ s/.*::///r);
    $type2class{$type}   = $class;
}

sub type2class($)  { $type2class{$_[1]} }
sub types()        { [ keys %type2class ] }
sub all_column_classes() { [ values %type2class ] }

sub attributes_for($)
{   my ($thing, $type) = @_;
    my $class = $type2class{$type} or panic;
    @generic_attributes, @{$class->option_names};
}

#XXX some of these should have been named is_*()
sub addable        { 0 }   # support sensible addition/subtraction
sub can_multivalue { 0 }   #XXX same as multivalue?
sub fixedvals      { 0 }
sub form_extras($) { panic } # returns extra scalar and array parameter names 
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

# $self->valid_value($value, %options)
# option 'fatal'
sub valid_value   { 1 }   

has set_values => (
    is      => 'rw',
    trigger => sub { shift->build_values(@_) },
);

sub name_long() { $_[0]->name . ' (' . $_[0]->sheet->name . ')' }

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

has set_display_fields => (
    is        => 'rw',
    predicate => 1,
);

has display_fields => (
    is      => 'rw',
    lazy    => 1,
    coerce  => sub {
        my $val = shift;
        ref $val eq 'Linkspace::Filter' ? $val : Linkspace::Filter->from_json($val);
    },
#XXX
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

#XXX the actual value is never used
sub do_group_display() { $_[0]->numeric ? 'sum' : $_[0]->group_display }

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
    my $json = $self->display_field_json or return undef;
    encode_base64 $json, ''; # base64 plugin does not like new lines in content
}

has link_parent => (
    is      => 'lazy',
    builder => sub { $_[0]->column($_[0]->link_parent_id) },
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

sub dependencies_ids
{   my $self = shift;
    $self->has_display_field ? $self->display_field_col_ids : $self->depends_on_ids;
}

# Which columns depend on this field
has depended_by_ids => (
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
=head2 $column->column_update(%);
=cut

sub column_update($%)
{   my ($self, $update, %options) = @_;
    my $report = $args{report_only};

    my $new_id = $update->{related_field};
    notice __x"Update: related_field_id from {old} to {new}", 
        old => $self->related_field_id, new => $new_id
        if $report && $self->related_field_id != $new_id;

    delete $update{topic_id}
        unless $update{topic_id};  # only pos int

    $update{multivalue} ||= 0 if exists $update{multivalue};

    if(my $opts = $update->{options})
    {   $update->{options} = encode_json $opts if ref $opts eq 'HASH';
    }

    # XXX Move to curval class
    if ($self->type eq 'curval')
    {   $self->set_filter($original->{filter});
        $self->multivalue(1) if $self->show_add && $self->value_selector eq 'noshow';
    }

    $self->update($update);
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

    if(ref $self->tjoin)
    {   my ($left, $prefetch) = %{$self->tjoin}; # Prefetch table is 2nd part of join
        $select{prefetch} = $prefetch;
        $select{order_by} = "$prefetch.".$self->value_field; # Overrides
    }

    $::db->search($self->table => {
        'me.record_id'      => $record_ids,
        'layout.multivalue' => 1,
    }, \%select)->all;
}

# Used by cur* types
=head2 my $filter = $column->filter;
=head2 my $filter = $column->filter($update);
=cut

sub filter(;$)
{   my $self = shift;
    @_==1 or return Linkspace::Filter->from_json($self->filter_json, column => $self);

    # Via filter object, to ensure validation
    my $set    = shift;
    my $filter = blessed $set ? $set
       : Linkspace::Filter->from_json($set, column => $self);

    $self->update({filter => $filter->as_json});
    $filter;
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

=head2 \%changes = $class->collect_form($column, $sheet, \%params);
Process the C<%params> (coming from outside) into C<%changes> to be made to the
C<$column>.  When the C<$column> does not exist yet, some defaults will be added.
=cut

sub collect_form($$$)
{   my ($class, $old, $sheet, $params) = @_;
    my $layout = $sheet->layout;

    my $type = $params->{type} || ($old && $old->type)
        or error __"Please select a type for the item";

    my $impl = $class->type2class($type)
        or error __"Column type '{type}' not available", type => $type;

    my %changes;
    $changes{$_} = $params->{$_}
        for $class->attributes_for($type);

    unless(ref $changes{permissions})
    {   my %permissions;
        foreach my $perm (keys %params)
        {   $perm =~ m/^permission_(.*?)_(\d+)$/ or next;
            push @{$permissions{$2}}, $1;
        }
        $changes{permissions} = \%permissions;
    }

    if(my $short = $changes{name_short})
    {   $short =~ /^[a-z][_0-9a-z]*$/i
            or error __"Short names must begin with a letter and can only contain letters, numbers and underscores";

        my $exists = $layout->column($short);
		! $exists || ($old && $exists->id == $old->id)
            or error __x"Short name 'short' must be unique but already exists for field '{name}'",
            short => $short, name => $exists->name;
    }

    if($old)
    {   ! $impl->internal
            or error __"Internal fields cannot be edited";

        $old->sheet_id == $sheet_id
            or panic "Attempt to move column between sheets";
    }
    else
    {   $changes{remember} //= 0;
        $changes{isunique} //= 0;
        $changes{optional}   = exists $changes{optional} ? ($changes{optional}//0) : 1;
        $changes{position} //= $layout->highest_position + 1;
        $changes{width}    //= 50;
        $changes{name} or error __"Please enter a name for item";
    }

    if(my $dc = $changes{display_condition} =~ s/\h+$//r)
    {   $dc eq 'AND' || $dc eq 'OR'
            or error __"Unknown display_condition '{dc}'", dc => $dc;
    }

    if(my $link_parent = $layout->column($insert{link_parent}))
    {    # Check whether the parent linked field goes to a layout that has a curval
         # back to the current layout: no reference loop
         ! $link_parent->refers_to_sheet($layout->sheet)
            or error __x"Cannot link to column '{col}' which contains columns from this sheet",
                col => $link_parent->name;
    }

    if(my $opt = $changes{options})
    {   $changes{options} = encode_json $opt if ref $opt;
    }

    my %extra;
    my ($extra_scalars, $extra_arrays) = $class->form_extras;
    $extra{$_} = $params->{$_} for @$extra_scalars;
    $extra{$_} = [ $params->get_all($_) ] for @extra_arrays;
    $extra{no_alerts} = delete $extra{no_alerts_rag} || delete $extra{no_alerts_calc};
    $extra{code}      = delete $extra{code_rag} || delete $extra{code_calc};
    $extra{no_cache_update}
       = delete $extra{no_cache_update_rag} || delete $extra{no_cache_update_calc};
    $changes{extra} = \%extra;

    \%changes;
}


#XXX Apparently only of interest to curval
sub refers_to_sheet($) { 0 }

sub column_create
{   my ($class, $sheet, \%insert) = @_;

    my $display_field = delete $insert->{display_field};
    my $extra         = delete $insert->{extra};
    my $perms         = delete $insert->{permissions};
    $insert->{display_condition} = $display_field->as_hash->{condition};

    my $col_id = $::db->create(Layout => \%insert);
    my $column = $class->from_id($col_id, sheet => $sheet);

    $column->column_extra_update($extra);
    $column->column_perms_update($perms);
    $column->display_fields_update($display_field);
    $self->after_write_special(%options);
    #$self->_write_permissions(id => $col_id, %options);
}

sub display_fields_update($)
{   my ($self, $display_fields) = @_;
    my $col_id = $self->id;

    # Write display_fields
    $::db->delete(DisplayField => { layout_id => $col_id });

    foreach my $cond (@{$display_fields->filters})
    {
        $cond->{column_id} == $col_id
            and error __"Display condition field cannot be the same as the field itself";

        $::db->create(DisplayField => {
            layout_id        => $col_id,
            display_field_id => $cond->{column_id},
            regex            => $cond->{value},
            operator         => $cond->{operator},
        });
    }
}

sub user_can
{   my ($self, $permission, $user) = @_;
    return 1 if  $self->internal  && $permission eq 'read';
    return 0 if !$self->userinput && $permission ne 'read'; # Can't write to code fields

    $user ||= $::session->user;
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

has permissions => (
    is      => 'lazy',
    builder => sub { ... },
);

sub column_perms_update($)
{   my ($self, $new_perms) = @_;
    defined $new_perms or return;

    my $old_perms = $self->permissions;
    $self->permissions($new_perms);

    # detect removed groups
    $new_perms{$_} ||= [] for keys %$old_perms;

    my $col_id    = $self->col_id;

    foreach my $group_id (keys %$new_perms)
    {   my %old_perms = map +($_ => 1), @{$old_perms{$group_id}};
        my @my_perms  = (layout_id => $col_id, group_id => $group_id);

        foreach my $perm (@{$new_perms{$group_id}})
        {   next if delete $old_perms{$perm};

            notice __x"Add permission {perm} for group {group} to column '{column}'"
                perm => $perm, column => $self->name, group => $group_id;

            $::db->create(LayoutGroup => { @my_perms, permission => $perm });
        }

        foreach my $perm (keys %old_perms)
        {    notice __x"Removed permission {perm} for group {group} from column '{column}'",
                perm => $perm, column => $self->name, group => $group_id;

            $::db->delete(LayoutGroup => { @my_perms, permission => $perm });
        }

        $old_perms{read} or next;

        ### Read-rights has been removed, which triggers major changes.
        #   permissions already withdrawn: check whether there are some left.

        my $views = $self->sheet->views;
        foreach my $sort ( @{$self->sorts} ) {
            my $owner = $views->view($sort->view_id)->owner;
            $sort->delete if $owner && !$self->user_can(read => $owner);
        }

        foreach my $filter ( @{$self->filters} ) {
            my $owner = $filter->view->owner;
            next if !$owner || $self->user_can(read => $owner);

            $view->unuse_column($column);

            # Filter cache
            $filter_ref->delete;

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
            $view->filter_remove_column($column);
        }
    }
}

has filters => (
    is      => 'lazy',
    builder => sub
    {   my @refs  = $::db->search(Filter => { layout_id => $self->id })->all;
        my $views = $self->sheet->views;
        [ map $views->view($_->view_id)->filter($_->id), @refs ];
    }
}

sub validate_search
{   shift->validate(@_);
#XXX
}

# Default sub returning nothing, for columns where a "like" search is not
# possible (e.g. integer)
sub resultset_for_values {}

sub values_beginning_with
{   my ($self, $match_string, %options) = @_;

    my $resultset = $self->resultset_for_values
        or return ();

    my @value;
    my $value_field = 'me.'.$self->value_field;

    $match_string =~ s/([_%])/\\$1/g;
    my $search = $match_string
        ? { $value_field => { -like => "${match_string}%" } }
        : {};

    my $match_result = $resultset->search($search, { rows => 10 });
    if($options{with_id} && $self->fixedvals)
    {
        @value = map +{
           id   => $_->get_column('id'),
           name => $_->get_column($self->value_field),
        }, $match_result->search({}, columns => ['id', $value_field]})->all;
    }
    else {
    {   @value = $match_result->search({}, {
            select => { max => $value_field, -as => $value_field },
        })->get_column($value_field)->all;
    }

    @value;
}

# The regex that will match the column in a calc/rag code definition
sub code_regex
{   my $self   = shift;
    my $name   = $self->name;
    my $suffix = $self->suffix;
    qr/\[\^?\Q$name\E$suffix\]/i;
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

