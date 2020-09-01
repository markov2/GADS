package Linkspace::DB::Table;

use Log::Report 'linkspace';
use Moo;
use Scalar::Util qw/blessed/;
use JSON         qw/encode_json/;

=head1 NAME
Linkspace::DB::Table - based on a table

=head1 SYNOPSIS
  use Moo;
  extends 'Linkspace::DB::Table';

  sub db_table { 'Site' }
  sub db_field_rename { +{} }
  sub db_fields_unused { [] }
  sub db_no_export { [] }

=head1 DESCRIPTION
Use this base class for all objects in the C<Linkspace> namespace which are
abstracting table data.

Objects get read-only access to the table records.  Only the specialized
C<update()> and C<create()> methods are permitted to write to the table.

=head1 METHODS: Class constructors

=head1 $class->db_accessors;
=cut

sub db_accessors(%)
{   my ($class, %args) = @_;

    my $table  = $class->db_table;
    my $rclass = $class->db_result_class;

    #XXX some packages are loaded, but not all.  Why not?
    eval "require $rclass" or panic $@;

    my $info   = $rclass->columns_info or panic "schema $rclass not loaded";
    my $rename = $class->_db_rename($info);

    no strict 'refs';

    foreach my $acc ( @{$class->db_fields_unused} )
    {   $info->{$acc} or panic "Non-existing field $acc";
        *{"${class}::$acc"} = eval <<__STUB;
sub { error "Field $acc in $table not expected to be used" }
__STUB
    }

    foreach my $acc (keys %$info)
    {   my $attr = $rename->{$acc} || $acc;
        next if $class->can($attr);

        # We peak directly inside the record object to avoid slow (smart)
        # accessors from DBIx::Class.  Same as $self->_record->$acc()
        *{"${class}::$attr"} = eval <<__ACCESSOR;
sub { \@_==1 or error "Read-only accessor ${class}::$attr"; \$_[0]{_coldata}{$acc} }
__ACCESSOR
    }

#XXX would like to install this helper, but the original names often have a new
#XXX implementation, for instance ::Column::link_parent()
#   foreach my $acc (keys %$rename)
#   {   next if $class->can($acc);  # some other implementation of the method
#       *{"${class}::$acc"} = eval <<__RENAME;
#sub { error "Accessor ${class}::$acc renamed to $rename->{$acc}" }
#__RENAME
#    }
}

# To be overwritten
sub db_table        { panic "no method db_table() in $_[0]" }
sub db_result_class { 'GADS::Schema::Result::' . $_[0]->db_table }

# You may want to use different names for some accessors than used by the
# database.  Of course, it would be better to change the database field names
# themselves, but that's quite some effort.  Explicitly: rename all fields which
# accidentally lack a _id but are numeric identifiers.
sub db_field_rename { +{} }
sub db_fields_unused { [] }

sub _db_rename(;$)
{   my ($thing, $info) = @_;
    $info ||= $thing->db_result_class->columns_info;
    my %rename = %{$thing->db_field_rename};
    $rename{instance_id} = 'sheet_id'    if $info->{instance_id};
    $rename{layout_id}   = 'column_id'   if $info->{layout_id};
    $rename{record_id}   = 'revision_id' if $info->{record_id};
    \%rename;
}

# Specify which db-fields are only internally for the application, so not
# involved in exporting and importing records.
sub db_fields_no_export { [] }

# Specify database fields which are booleans.  Do use 'db_also_bools'
# sparsely: only when it is really obvious from the field name that this
# is a boolean.  In the current scheme, that's rarely the case.
sub _is_boolean_field_name($) { $_[0] =~ /^(?:is|can|do|has|no|needs)_/ }
sub db_also_bools { [] }

#-----------------------
=head1 METHODS: Constructors

=head2 my $object = $class->from_record($record, %options);
When you have a C<$record> from the right type (the result class of the
table), this gets wrapped into a full Linkspace object.  The C<%options>
are the attributes for the created object, processed Moo style.
=cut

sub from_record($%)
{   my ($class, $record) = (shift, shift);
    defined $record or return;

    $record->isa($class->db_result_class)
        or panic "wrong record of type, ".(ref $record);

    $record ?  $class->new(@_, _record => $record) : undef;
}

=head2 my $object = $class->from_id($obj_id, %options);
Create the C<$object> which manages a database record, based on the
unique C<id> column in the table.
=cut

sub from_id($%)
{   my ($class, $obj_id) = (shift, shift);
    $obj_id or return;

    my $record = $::db->get_record($class->db_table => $obj_id);
    $record ? $class->from_record($record, @_) : undef;
}

=head2 my $object = $class->from_search(\%search, %options);
Create the C<$object> which manages a database record.  The search must
result in at most one record.
=cut

sub from_search($%)
{   my $class  = shift;
    my $search = $class->_record_converter->(shift);
    my $record = $::db->get_record($class->db_table => $search);
    $record ? $class->from_record($record, @_) : undef;
}

=head2 \@records = $class->search_records(\%search);
Returns records (Schema::Result objects).  The search query should use
the renamed field, and cannot be complex (for the moment).
=cut

sub search_records($)
{   my ($thing, $search) = @_;
    [ $::db->search($thing->db_table, $thing->_record_converter->($search))->all ];
}

=head2 \@objects = $class->search_objects(\%search, %options);
Uses C<search_records()> to find records, and than converts them into
the related objects.
=cut

sub search_objects($%)
{   my ($thing, $search) = (shift, shift);
    my $records = $thing->search_records($search || {});
    [ map $thing->from_record($_, @_), @$records ];
}

#-----------------------
=head1 METHODS: Attributes

=head2 my $path = $obj->path;
Returns an impression of the object location in the logical tree, especially
used for logging.
=cut

sub path() { panic "path() not implemented for ".ref $_[0] }

# This attribute shall not be used outside the object which manages the table:
# always use clean abstraction to address the fields.
has _record => (
    is       => 'ro',
    required => 1,
    trigger  => sub { $_[0]{_coldata} = $_[1]{_column_data} },
);

# Very dirty: poke directly in the body of the ::Result object.
sub _coldata { $_[0]{_coldata} }

=head2 my $column = $obj->column($which);
Many objects address columns: to simplify access it got an efficient call.
When the object relates to a sheet, that C<columns()> is called which
prefers local names when they are used.  Otherwise, the lookup is in
the site-wide column index.
=cut

# Cache the looked-up function address which translates column ids/name into
# column objects.  This will add some speed.
has _get_column => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        ( $self->can('sheet_id') || $self->can('sheet')
        ? $self->sheet->layout
        : $::session->site->document
        )->can('column');
    },
);

sub column($) { $_[0]->_get_column->($_[1]) }

=head2 my $sheet = $obj->sheet;
Returns the Sheet where the object belongs to, if defined.  Often this
is passed explicitly when the object get's created... but can also be
looked-up under fly.
=cut

has sheet => (
    is      => 'lazy',
    weakref => 1,
    builder => sub
    {   my $self = shift;
        $self->can('sheet_id') or panic "Object is not related to a sheet";
        $self->site->sheet($self->sheet_id);
    },
);

=head2 my $layout = $obj->layout;
Returns a L<Linkspace::Sheet::Layout> object, which administers the columns
in the active sheet.
=cut

sub layout { $_[0]->sheet->layout }

=head2 my $site = $obj->site;
Returns the active site object.
=cut

sub site { $::session->site }

#-----------------------
=head1 METHODS: Simple database access

=head2 \%h = $obj->export_hash(%options);
Returns all fields which are interesting to export via a CSV.
The C<db_fields_unused()> and C<db_fields_no_export()> get excluded by
default.  You may want to override this method with tricks.

The field names are (at the moment) equal to the column names in the database,
for backwards compatibility, unless you set option C<renamed>.  You may also
use C<exclude_undefs>.
=cut

sub export_hash($)
{   my ($self, %args) = @_;
    my %h       = %{$self->{_coldata}};

    my $exclude = $self->db_fields_no_export;
    delete @h{@$exclude} if @$exclude;

    my $unused  = $self->db_fields_unused;
    delete @h{@$unused}  if @$unused;

    if($args{exclude_undefs})
    {   delete $h{$_} for grep !defined $h{$_}, keys %h;
    }

    if($args{renamed})
    {   my $rename = $self->_db_rename;
        $h{$rename->{$_}} = delete $h{$_} for grep exists $h{$_}, keys %$rename;
    }
    \%h;
}

=head2 $obj->delete(%options);
Remove the record for this object from the database.
=cut

sub delete
{   my ($self, %args) = @_;
    $self->_record->delete;

    info __x"{obj.db_table} {obj.id}='{obj.path}' deleted", obj => $self
        unless $args{lazy};

    1;
}

=head2 $obj->update(\%update, %options);
Change the database fields for the record.  Read about field rewrite rules below.

When option C<lazy> is set, the changes are not applied to the loaded object:
this may be a bit faster for bulk uploads... but also be cause for unexpected
results when the object gets used immediately after the update.
=cut

sub update($%)
{   my ($self, $values, %args) = @_;
    my $update = $self->_record_converter->($values);
    keys %$update or return;

    unless($args{lazy})
    {   #MO: I had expected DBIx::Class would do this, but no.
        my $record = $self->_record;
        $record->$_($update->{$_}) for keys %$update;

        info __x"{obj.db_table} {obj.id}='{obj.path}' changed fields: {fields}",
            obj => $self, fields => [ sort keys %$update ];
    }

    $::db->update($self->db_table, $self, $update);
    $self;
}

=head2 my $object = $class->create(\%insert, %options);
Create a new record in the database, in the specific table.  Read about field
rewrite rules below.

With option C<lazy> set, the instantiated object will not be returned
and creation not logged: mainly for bulk import.

With C<record_field_names>, you need to used the field names as in the database
table.  You do not get any automatic conversion tricks.
=cut

sub create($%)
{   my ($class, $values, %args) = @_;
    my $insert = $args{record_field_names} ? $values
      : $class->_record_converter->($values);

    my $result = $::db->create($class->db_table, $insert);

    return undef if $args{lazy};

    my $self   = $class->from_id($result->id, %args);
    info __x"{class.db_table} created {obj.id}: {obj.path}",
        class => $class, obj => $self;

    $self;
}

=head2 ($add, $rem, $ch) = $class->set_record_list(\%set, \@items, \&eq?);
Implements logic for a simple 'has many' relation update.  It adds
and removes C<@items> from the database.  Each item is a record.

The C<%set> contains a query which selects all items which belong to
the list.  Those fields do not (need to) be part of each of the items:
they get itemed automatically.

You may use the returned ARRAY of C<$added>, C<$removed> and C<$changed>
record ids to update your indexes.  This method does not know anything
about cached objects or already instantiated objects.

When you specify a C<&eq> sub, it will be used to find-out which records
are already present.  If needed, it will only update those records.  When
there is no such routine all existing records will get replaced by new
ones.
=cut

# This code is larger than simply needed to maintain an easy 'has many'
# relation, because it is requires some flexibility.

sub set_record_list($$;$)
{   my ($class, $select, $items, $equal) = @_;
    defined $items or return;

    my $table = $class->db_table;
    my $conv  = $class->_record_converter;
    my $set   = $conv->($select);
    my @old   = $::db->search($table, $set)->all;

    unless(@$items)
    {   my @removed = map $_->id, @old;
        $::db->delete($table => $set);
        info __x"bulk update {table} table removed all {removed} records",
            table => $table, removed => scalar @removed if @removed;
        return ([], \@old, []);
    }

    my @records  = map $conv->($_), @$items;

    unless($equal)
    {   # Don't know how elements can be kept: replace all existing
        my @removed = map $_->id, @old;
        $::db->delete($table => $set);
        my @created = map $::db->create($table => {%$set, %$_})->id, @records;
        info __x"bulk update {table} table, created {created}, removed {removed} records", 
            table   => $table, created => scalar @created,
            removed => scalar @removed;
        return (\@created, \@removed, []);
    }

    my %old = map +($equal->($_->{_column_data}) => $_), @old;
    my (@created, @changed);

    foreach my $record (@records)
    {
       if(my $has = delete $old{$equal->($record)})
       {   my $data = $has->{_column_data};
           ($record->{$_} // '\0') eq ($data->{$_} // '\0') && delete $record->{$_}
               for keys %$record;

            if(keys %$record)
            {   $::db->update($table => $has->id, $record);
                push @changed, $has->id;
            }
        }
        else
        {   push @created, $::db->create($table => { %$set, %$record })->id; 
        }
    }

    my @removed = map $_->id, values %old;
    $::db->delete($table => { id => \@removed }) if @removed;

    info __x"bulk update {table} table, created {created}, removed {removed}, changed {changed} records",
        table   => $table, created => scalar @created,
        removed => scalar @removed, changed => scalar @changed;

    ( \@created, \@removed, \@changed );
}

#------------------
=head1 DETAILS

=head2 Explain Record Conversion

In the original GADS code, it is sometimes hard to see whether a field is a
boolean, contains JSON, or contains an id.  Over time, there may be a database
rename projects, but for the moment, we solve this by mapping better (internal)
names to the problematic database (external) names.

(Renamed) field names which end on C<_id> expect and integer id, refering to
an object.  The same name without C<_id> can also be used: but in that case you
can also provide an object which id is automatically taken.

(Renamed) field names which end on C<_json> can be used with either a HASH
or a JSON string.  You may also use the name without C<_json> with the same
result.

(Renamed) field names which start with C<is_>, C<can_>, C<do_>, or
C<has_> are treated as booleans.  Also fields which end on C<_mandatory>
are boolean.  Trues values become 1, false values become 0.  So: no need
for C<<$condition ? 0 : 1>> anymore.
=cut

sub _record_converter
{   my $thing  = shift;
    my $class  = ref $thing || $thing;
    my $info   = $class->db_result_class->columns_info;
    my $unused = $class->db_fields_unused;
    my $rename = $class->_db_rename($info);
    my %bools  = map +($_ => 1), @{$class->db_also_bools};

    my %map    = (
        (map +($_ => $_), keys %$info),
        %$rename,
    );

    my %run;
    foreach my $k (@$unused)
    {   $run{$k} = sub { panic "Key $k is flagged unused" };
        delete $map{$k};
    }

    my $make = sub    # compile, not closures for performance
      { my ($int, $take) = @_;
        eval "sub { \$_[1]{$int} = $take }" or panic $@;
      };

    while(my ($int, $ext) = each %map)
    {	$info->{$int} or panic "No '$ext' in $class";

        if($ext =~ /(.*)_id$/)
        {   $run{$1}    ||= $make->($int, 'blessed $_[0] ? $_[0]->id : $_[0]');
            $run{$ext}  ||= $make->($int, '$_[0]');
        }
        elsif(_is_boolean_field_name($ext) || $bools{$int} )
        {   $run{$ext}  ||= $make->($int, '$_[0] ? 1 : 0');
        }
        elsif($ext =~ /(.*)_json$/)
        {   my $base = $1;
            my $json = $make->($int, 'ref $_[0] eq "HASH" ? encode_json $_[0] : defined $_[0] ? $_[0] : "{}"');
            $run{$base} ||= $json;
            $run{$ext}  ||= $json;
        }
        else
        {   $run{$ext}  ||= $make->($int, '$_[0]');
        }
    }

    $run{$_} ||= sub { panic "Old key '$_' used, should be '$map{$_}'" }
        for keys %map;

    my $converter = sub {
        my $in  = shift;
        my $out = {};
        ($run{$_} or panic "Unusable $_")->($in->{$_}, $out) for keys %$in;
        $out;
    };

    no strict 'refs';
    *{"${class}::_record_converter"} = sub { $converter };
    $converter;
}

1;
