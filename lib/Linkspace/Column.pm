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
use JSON          qw/decode_json encode_json/;

use Linkspace::Util  qw/flat/;

use Linkspace::Filter::DisplayField ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table';

#use namespace::clean; # Otherwise Enum clashes with MooseLike
#with 'Linkspace::Role::Presentation::Column';

sub db_table() { 'Layout' }

sub db_field_rename { +{
    display_field => 'display_field_old',  #XXX to be removed
    filter        => 'filter_json',
    internal      => 'is_internal',
    isunique      => 'is_unique',
    link_parent   => 'link_parent_id',
    multivalue    => 'is_multivalue',
    optional      => 'is_optional',
    options       => 'options_json',
    related_field => 'related_column_id',
    textbox       => 'is_textbox',
} }

sub db_fields_also_bool { [ qw/end_node_only/ ] }

# The display_field is now in a separate table.
sub db_fields_unused    { [ qw/display_matchtype display_regex permission/ ] }

my @fields_limited_use = (
    'end_node_only',    # tree
    'filter',           # curval
    'force_regex',      # string
    'is_textbox',       # string
    'ordering',         # enum
    'related_column',   # autocur
);

# Some of the generic fields are limited in use for certain types
sub db_field_extra_export { [] }
sub db_fields_no_export
{   my $self = shift;
    my %exclude = map +($_ => 1), qw/display_field/, @fields_limited_use;
    delete $exclude{$_} for @{$self->db_field_extra_export};
    [ keys %exclude ];
}

#XXX change these
my @public_attributes = qw/description helptext is_unique link_parent_id
    is_multivalue name name_short optional remember can_child topic_id
    type width/;
my @simple_import_attributes = 
   qw/name name_short optional remember isunique can_child position description
      aggregate width filter helptext multivalue group_display/;


__PACKAGE__->db_accessors;

### 2020-04-14: columns in GADS::Schema::Result::Layout
# id                display_field     internal          permission
# instance_id       display_matchtype isunique          position
# name              display_regex     link_parent       related_field
# type              end_node_only     multivalue        remember
# aggregate         filter            name_short        textbox
# can_child         force_regex       optional          topic_id
# description       group_display     options           typeahead
# display_condition helptext          ordering          width


###
### META information about the column implementations.
#   These are class constants, very rarely flexible. It would be nicer
#   to make a ::Meta object, however: in that case the programmer must
#   be aware which methods are in meta...

my %type2class;

sub register_type(%)
{   my ($class, %args) = @_;
    my $type = $args{type} || lc($class =~ s/.*:://r);
    $type2class{$type}   = $class;
}

sub type2class($)  { $type2class{$_[1]} }
sub types()        { [ keys %type2class ] }
sub all_column_classes() { [ values %type2class ] }

=head1 METHODS: Constructors
=cut

sub from_record($%)
{   my ($class, $record) = (shift, shift);
    defined $record or return;

      $class eq __PACKAGE__
    ? $type2class{$record->type}->from_record($record, @_)
    : $class->SUPER::from_record($record, @_);
}

###
### META
###

#XXX some of these should have been named is_*()
sub is_addable     { 0 }       # support sensible addition/subtraction
sub can_multivalue { 0 }
sub has_fixedvals  { 0 }
sub form_extras($) { [], [] }  # returns extra scalar and array parameter names
sub has_cache      { 0 }       #XXX autodetect with $obj->can(write_cache)?
sub has_filter_typeahead { 0 } # has typeahead when inputting filter values
sub has_multivalue_plus  { 0 }
sub is_hidden      { 0 }       # column not shown by default (only deletedBy)
sub is_internal_type { 0 }     # the type is internal, see is_internal() on objects
sub is_curcommon   { 0 }
sub meta_tables    { [ qw/String Date Daterange Intgr Enum Curval File Person/ ] }
sub option_defaults{ shift;  +{ @_ } }
sub option_names   { [ keys %{$_[0]->option_defaults} ] }
sub retrieve_fields{ [ $_[0]->value_field ] }
sub return_type    { 'string' }
sub sort_field     { $_[0]->value_field }
sub is_userinput   { 1 }
sub value_field    { 'value' }
sub value_to_write { 1 }      #XXX only in Autocur, may be removed
sub variable_join  { 0 }      # joins can be different on the config

# Whether the sort columns when added should be added with a parent, and
# if so what is the parent.  Default no, undef in case used in arrays.
sub sort_parent   { undef }

# Attributes which can be set by a user

###
### Class
###

sub _validate($)
{   my ($thing, $update) = @_;
    my $name = blessed $thing ? $thing->name_short : $update->{name_short};

    unless($update->{extras})
    {   # Separate out which parameters are specific for specific types.
        my %extras;
        my ($s, $a) = $thing->form_extras;
        $extras{$_} = delete $update->{$_}
            for grep exists $update->{$_} && ! __PACKAGE__->can($_), @$s, @$a;
        $update->{extras} = \%extras;
    }

    if(my $dc = $update->{display_condition})
    {   $dc eq 'AND' || $dc eq 'OR'
            or error __x"Column {name} with unsupported display_condition operator '{dc}'",
                name => $name, dc => $dc;
    }

    # In a number of cases, the Layout-record has columns which are specific for
    # a single type.  But in other cases, specifics are stored in an 'options' HASH
    # which is kept as JSON (hence not searchable)  Updates are tricky.
    my $opts = $update->{options};
    foreach my $name ($thing->option_names)
    {   exists $update->{$name} or next;
        $opts ||= ref $thing ? $thing->options : $thing->option_defaults;
        $opts->{$name} = delete $update->{$name} // 0;  # some are bools
    }
    $update->{options} = $opts if $opts;

    ! $update->{is_multivalue} || $thing->can_multivalue
        or error __x"Column {name} cannot multivalue", name => $name;

    $update;
}

sub _column_create
{   my ($base_class, $insert, %args) = @_;
    my $class = $type2class{$insert->{type}}  or panic;
    $insert->{name} //= $insert->{name_short};

    $insert->{options} = $class->option_defaults;  # modified in validate()
    $class->_validate($insert);

    $insert->{is_internal} //= $class->is_internal_type;
    $insert->{display_condition} ||= 'AND';

    my $df    = delete $insert->{display_field};
    my $perms = delete $insert->{permissions};
    my $extra = delete $insert->{extras};

    $insert->{is_textbox}    //= 0;
    $insert->{end_node_only} //= 0;
    my $self = $class->create($insert, sheet => $insert->{sheet});

    $self->_column_extra_update($extra, %args);
    $self->_column_perms_update($perms) if $perms;
    $self->_display_field_update($df)   if $df;
    $self;
}

# Process all arguments from the configuration which is column type specific.
sub _column_extra_update($) {}

sub _column_update($%)
{   my ($self, $update, %args) = @_;
    $self->_validate($update);
    $self->_column_extra_update(delete $update->{extras}, %args);

    $self->_display_fields_update(delete $update->{display_field})
        if exists $update->{display_field};

    $self->update($update);
    $self;
}

###
### Instance
###

=head2 my $s = $column->as_string(%options);
Present the column as a text block.  Primarily used for debugging.
=cut

sub as_string(%)
{   my ($self, %args) = @_;
    my $special = $self->_as_string(%args) // '';
    if(length $special)
    {   $special =~ s/^/    /gm;
        $special =~ s/^/\n/;
    }

    sprintf "%-11s %s%s%s%s %s%s\n", $self->type,
        ($self->is_internal   ? 'I' : ' '),
        ($self->is_multivalue ? 'M' : ' '),
        ($self->is_optional   ? 'O' : ' '),
        ($self->is_unique     ? 'U' : ' '),
        $self->name_short, $special;
}
sub _as_string { '' }

sub path { $_[0]->sheet->path .'/'. $_[0]->type .'='. $_[0]->name_short }

sub is_numeric { 0 }    # some fields can contain flexible types
sub name_long  { $_[0]->name . ' (' . $_[0]->sheet->name . ')' }
sub filter_value_to_text { $_[1] }
sub value_field_as_index { $_[0]->value_field }

# Used when searching for a value's index value as opposed to
# string value (e.g. enums)
sub sort_columns   { [ $_[0] ] }

# Whether the data is stored as a string. If so, we need to check for both
# empty string and null values to test if empty
sub string_storage { 0 }

sub returns_date   { $_[0]->return_type =~ /date/ }   #XXX ^date ?
sub field_name     { "field".($_[0]->id) }
sub datum_class    { ref $_[0] =~ s/::Column/::Datum/r }

# my $v = $self->is_valid_value($value)
sub is_valid_value($)
{   my ($self, $values) = @_;
    my @v = grep defined, flat $values;
    unless(@v)
    {   return $self->is_multivalue ? [] : undef if $self->is_optional;
        error __x"Column \'{name}\' requires a value.", name => $self->name;
    }

    return $self->_is_valid_value($v[0])
        if @v==1;

    $self->is_multivalue
        or error __x"Column \'{name}\' is not a multivalue.", name => $self->name;

    [ map $self->_is_valid_value($_), @v ];
}

sub topic { $_[0]->sheet->topic($_[0]->topic_id) }

has link_parent => (
    is      => 'lazy',
    builder => sub { $_[0]->column($_[0]->link_parent_id) },
);


#### query build support
sub sprefix    { $_[0]->field_name }

#XXX can be HASH, ARRAY or a single value.
sub tjoin      { $_[0]->field_name }

sub suffix()
{   my $self = shift;
      $self->return_type eq 'date' || $self->return_type eq 'daterange'
    ? '(\.from|\.to|\.value)?(\.year|\.month|\.day)?'
    : '';
}

# Used to provide a blank template for row insertion (to blank existing
# values). Only used in calc at time of writing
sub blank_row { +{ $_[0]->value_field => undef }; }

sub parse_date
{   my ($self, $value) = @_;
    return if ref $value;

    # Check whether it's a CURDATE first
    my $dt = Linkspace::Filter->parse_date_filter($value);
    return $dt if $dt;

    $self->site->local2dt(auto => $value);  #XXX auto? or can we do more specific
}

sub remove_all_permissions() { ... }  #XXX for testing
sub set_permissions($$)
{   my ($self, $group, $perms) = @_;
    ...;
}

sub permissions_by_group_export()
{   my $self = shift;
    my %permissions;
return {};
#XXX
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

    my %groups;
    foreach my $perm ($self->_access_groups)
    {   my $p = GADS::Type::Permission->new(short => $perm->permission);
        push @{$groups{$perm->group->name}}, $p->medium;
    }

    local $" = ', ';
    join "\n", map qq(Group "$_" has permissions: @{$groups{$_}}\n),
        sort keys %groups;
}

#-----------------------
=head1 METHODS: Filters
::Layout::columns_for_filter() will change these to include parent information.
XXX this is a bad idea!
=cut

# ID for the filter
has filter_id => (
    is      => 'rw',
    default => sub { $_[0]->id },
);

# Name of the column for the filter
has filter_name => (
    is      => 'rw',
    default => sub { $_[0]->name },
);

# Generic subroutine to fetch all multivalues for a table. Designed to satisfy
# most standard tables. Overridden for anything complicated.
sub fetch_multivalues
{   my ($self, $record_ids) = @_;

    my %select = (
        join       => 'layout',
        result_set => 'HASH',
    );

    my $t = $self->tjoin;
    if(ref $t)
    {   my ($left, $prefetch_table) = %$t;
        $select{prefetch} = $prefetch_table;
        $select{order_by} = $prefetch_table . "." .$self->value_field;
    }
    else
    {   $select{order_by} = "me.".$self->value_field;
    }

    $::db->search($self->table => {
        'me.record_id'      => $record_ids,
        'layout.multivalue' => 1,
    }, \%select)->all;
}

=head2 $column->remove_history;
Clean up any specialist data for all column types. The column's type may have
changed during its life, but the data may not have been removed on changed,
so we have to check all classes.
=cut

sub remove_history()
{   my $self = shift;
    $_->_remove_column($self) for @{$self->all_column_classes};
}

=head2 \%changes = $class->collect_form($column, $sheet, \%params);
Process the C<%params> (coming from outside) into C<%changes> to be made to the
C<$column>.  When the C<$column> does not exist yet, some defaults will be added.
=cut

sub collect_form($$$)
{   my ($class, $old, $sheet, $params) = @_;
    my $layout   = $sheet->layout;
    my $sheet_id = $sheet->id;

    my $type = $params->{type} || ($old && $old->type)
        or error __"Please select a type for the item";

    my $impl = $class->type2class($type)
        or error __"Column type '{type}' not available", type => $type;

    my %changes;
    $changes{$_} = $params->{$_}
        for @public_attributes, @{$class->option_names};

    unless(ref $changes{permissions})
    {   my %permissions;
        foreach my $perm (keys %$params)
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

    if(!$old)
    {   $changes{remember}  //= 0;
        $changes{is_unique} //= 0;
        $changes{is_optional} = exists $changes{is_optional} ? $changes{is_optional} : 1;
        $changes{width}     //= 50;
        $changes{name} or error __"Please enter a name for item";
    }

    if(my $link_parent = $layout->column($params->{link_parent_id}))
    {    # Check whether the parent linked field goes to a sheet that has a curval
         # back to the current layout: no reference loop
         ! $link_parent->refers_to_sheet($sheet)
            or error __x"Cannot link to column '{col}' which contains columns from this sheet",
                col => $link_parent->name;
    }

    delete $changes{topic_id}
        unless $changes{topic_id};  # only 1+

    my %extra;
    my ($extra_scalars, $extra_arrays) = $class->form_extras;
    $extra{$_} = $params->{$_} for @$extra_scalars;
    $extra{$_} = [ $params->get_all($_) ] for @$extra_arrays;
    $extra{no_alerts} = delete $extra{no_alerts_rag} || delete $extra{no_alerts_calc};
    $extra{code}      = delete $extra{code_rag} || delete $extra{code_calc};
    $extra{no_cache_update}
       = delete $extra{no_cache_update_rag} || delete $extra{no_cache_update_calc};
    $changes{extras} = \%extra;

    \%changes;
}


#XXX Apparently only of interest to curval
sub refers_to_sheet($) { 0 }

sub user_can
{   my ($self, $permission, $user) = @_;
    return 1 if  $self->is_internal  && $permission eq 'read';
    return 0 if !$self->is_userinput && $permission ne 'read';

    $user ||= $::session->user;
    if($permission eq 'write') # shortcut
    {   return 1
            if $user->can_column($self, 'write_new')
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
    $new_perms->{$_} ||= [] for keys %$old_perms;

    my $col_id    = $self->col_id;

    foreach my $group_id (keys %$new_perms)
    {   my %old_perms = map +($_ => 1), @{$old_perms->{$group_id}};
        my @my_perms  = (layout_id => $col_id, group_id => $group_id);

        foreach my $perm (@{$new_perms->{$group_id}})
        {   next if delete $old_perms{$perm};

            notice __x"Add permission {perm} for group {group} to column '{column}'",
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
            my $view  = $filter->view;
            my $owner = $view->owner;
            next if !$owner || $self->user_can(read => $owner);

            $view->unuse_column($self);

            # Filter cache
            $filter->delete;

            # And the JSON filter itself
            $view->filter_remove_column($self);
        }
    }
}

has filters => (
    is      => 'lazy',
    builder => sub
    {   my $self  = shift;
        my @refs  = $::db->search(Filter => { layout_id => $self->id })->all;
        my $views = $self->sheet->views;
        [ map $views->view($_->view_id)->filter($_->id), @refs ];
    },
);

=head2 $col->validate_search($value, %options);
Returns a true value when the C<$value> can be used as search query.
=cut

sub validate_search { 1 }

# Default sub returning nothing, for columns where a "like" search is not
# possible (e.g. integer)
sub resultset_for_values {}

sub values_beginning_with
{   my ($self, $match_string, %args) = @_;

    if($self->has_fixedvals)
    {   my $choices = $self->_values_beginning_with($match_string // '');
        $#$choices = 9 if @$choices > 10;
        return $args{with_id} ? $choices : [ map $_->{name}, @$choices ];
    }

    my $resultset   = $self->resultset_for_values or return ();
    my $value_field = 'me.'.$self->value_field;

    $match_string =~ s/([_%])/\\$1/g;
    my %search = $match_string
        ? ( $value_field => { -like => "${match_string}%" } )
        : ( );

    my $values_rs = $resultset->search(\%search, {
        select => { max => $value_field, -as => $value_field },
        rows   => 10,
    })->get_column($value_field);

    [ $values_rs->all ];
}

# The regex that will match the column in a calc/rag code definition
sub code_regex
{   my $self   = shift;
    my $name   = $self->name;
    my $suffix = $self->suffix;
    qr/\[\^?\Q$name\E$suffix\]/i;
}

sub additional_pdf_export {}

=head2 my $column = $class->import_hash($data, $layout, %options);
Consume data produced by C<export_hash()> into a new column in the sheet.
=cut

sub import_hash($$%)
{   my ($class, $layout, $values, %args) = @_;
    my %insert = map +($_ => $values->{$_}),
        @simple_import_attributes,
        @{$class->option_names};

    my $column = $layout->column_create(\%insert); 
    $column->_import_hash_extra($values, %args);
    $column;
}
sub _import_hash_extra($%) { shift }


sub export_hash
{   my ($self, %args) = @_;
    my $h = $self->SUPER::export_hash(%args);

=pod
    $h->{display_fields} = [ map +{
        id       => $_->{column_id},
        value    => $_->{value},
        operator => $_->{operator},
    }, @{$self->display_fields} ];
=cut

    $h->{permissions} = $self->permissions_by_group_export;
    $h;
}

# Subroutine to run after a column write has taken place for an import
#XXX
sub import_after_write {}

=head2 $class->how_to_link_to_record($record);
Tricky part, during schema initiation where methods are produced for fields.
=cut

sub how_to_link_to_record
{   my ($class, $record) = @_;

    ( $class->value_table, sub {
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

#---------------
=head2 METHODS: DisplayField
The Layout records contain a few DisplayField columns, which have been
replaced by a DisplayField table.  The table contains rules, and ::Column
weirdly carries the C<display_condition> to be used between those.
=cut

has display_field => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { Linkspace::Filter::DisplayField->from_column($_[0]) },
);

# During creation or update of a column.  May be a HASH (create) or
# undef (delete).
sub _display_field_update($)
{   my ($self, $rules) = @_;
    my $old = $self->display_field;

    if(!$rules)
    {   $old->_display_field_delete;
        $self->display_field(undef);
        return;
    }

    my $df = Linkspace::Filter::DisplayField->from_hash($rules, on_column => $self);
    $self->display_field($df);
    $df;
}

sub dependencies_ids
{   my $self = shift;
    my $df = $self->display_field;
    $df ? $df->column_ids : $self->depends_on_ids;
}


### Only used by Autocur/Curval
has related_field => (
    is      => 'lazy',
    builder => sub { $_[0]->column($_[0]->related_field_id) },
);

### Only used for Code
sub depends_on_columns { [] }

# Code overrides can_child()
# Code values always have their own child values if the record is a child, so
# that we build based on the true values of the child record.

### For visualizations only

sub widthcols
{   my $self = shift;
    my $multiplus = $self->is_multivalue && $self->has_multivalue_plus;
    $self->layout->max_width == 100 && $self->width == 50
    ? ( $multiplus ?  4 :  6)
    : ( $multiplus ? 10 : 12);
}

sub related_sheet_id() {
    my $column = $_[0]->related_field;
    $column ? $column->sheet_id : undef;
}

###
### Datums
###

sub datum_create($%)
{   my ($self, $values, %args) = @_;
    $self->datum_class->datum_create($values, column => $self);
}

1;
