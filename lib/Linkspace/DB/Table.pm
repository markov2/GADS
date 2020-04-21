package Linkspace::DB::Table;

use Log::Report 'linkspace';
use Moo;

=head1 NAME
Linkspace::DB::Table - based on a table

=head1 SYNOPSIS
  use Moo;
  extends 'Linkspace::DB::Table';

  sub db_table { 'Site' }
  sub db_field_rename { +{} }

=head1 DESCRIPTION
Use this base class for all objects in the C<Linkspace> namespace which are
abstracting table data.

Objects get read-only access to the table records.  Only the specialized
C<update()> and C<create()> methods are permitted to write to the table.

=head1 METHODS: Class constructors

=head1 $class->import;
=cut

sub import(%)
{   my ($class, %args) = @_;

    my $table   = $class->db_table;
    my $rclass  = $class->db_result_class;
    my $info    = $rclass->columns_info or panic "schema $rclass not loaded";

    my $rename = $class->db_field_rename;
    $rename->{instance_id} = 'sheet_id';

    foreach my $acc (keys %$info)
    {   my $attr = $rename->{$acc} || $acc;
        *{"${class}::$attr"} = eval <<__ACCESSOR;
sub { \@_==1 or panic "read-only accessor ${class}::$attr"; \$_[0]->_record->$acc }
__ACCESSOR
    }

    foreach my $acc ($class->db_fields_unused)
    {   *{"${class}::$acc"} = eval <<__STUMB;
sub { panic "field $acc in $table not expected to be used" }
    }
__STUMB
}

# To be overwritten
sub db_table        { panic "no \$db_table in $_[0]" }
sub db_result_class { 'GADS::Schema::Result::' . $_[0]->db_table }

# You may want to use different names for some accessors than used by the
# database.  Of course, it would be better to change the database field names
# themselves, but that's quite some effort.  Explicitly: rename all fields which
# accidentally lack a _id but are numeric identifiers.
sub db_field_rename { +{} }
sub db_fields_unused { () }

#-----------------------
=head1 METHODS: Constructors

=head2 my $object = $class->from_record($record, %options);
When you have a C<$record> from the right type (the result class of the table), this
gets wrapped into a full Linkspace object.  The C<%options> are the attributes
for the created object, processed Moo style.
=cut

sub from_record($%)
{   my ($class, $record) = (shift, shift);
    defined $record or return;

    $record->isa($class->db_result_class)
        or panic "wrong record of type, ".(ref $record);

    $record ?  $class->new(@_, _record => $record) : undef;
}

=head2 my $object = $class->from_id($obj_id, %options);
Create the C<$object> which manages a database record.
=cut

sub from_id($%)
{   my ($class, $obj_id) = (shift, shift);
    my $record = $::db->get_record($class->db_table => $obj_id);
    $record ? $class->new(@_, _record => $record) : undef;
}

#-----------------------
=head1 METHODS: Attributes

=cut

# This attribute shall not be used outside the object which manages the
# table: always use clean abstraction to address the fields.
has _record => (
	is       => 'ro',
    required => 1,
);

=head2 my $column = $obj->column($which);
Many objects address columns: to simplify access it got an efficient call.  When
the object relates to a sheet, that C<columns()> is called which prefers local
names when they are used.  Otherwise, the lookup is in the site wide column index.
=cut

# Cache the looked-up function address which translates column ids/name into
# column objects.
has _get_column => (
    lazy     => 1,
    builder  => sub
    {   my $self = shift;
        ( $self->has_sheet || $self->can('sheet_id')
        ? $self->sheet->layout
        : $::session->site->document
        )->can('column');
    }
);

sub column($) { $_[0]->_get_column->($_[1]) }

=head2 my $sheet = $obj->sheet;
Returns the Sheet where the object belongs to, if defined.  Often this
is passed explicitly when the object get's created... but can also be
looked-up under fly.
=cut

has sheet => (
    is        => 'lazy',
    weakref   => 1,
    predicate => 1,
    builder   => sub
    {   $_[0]->can('sheet_id') or panic "Object has no sheet";
        $::session->site->sheet($_[0]->sheet_id);
    },
);

=head2 my $layout = $obj->layout;
Returns a L<Linkspace::Sheet::Layout> object, which administers the columns
in the active sheet.
=cut

sub layout { $_[0]->sheet->layout }

#-----------------------
=head1 METHODS: Other methods

=head2 \%h = $obj->export_hash;
Returns all fields which are interesting to export via a CSV... by default
all but the 'id' fields.

The field names are (at the moment) equal to the column names in the database,
for backwards compatibility.
=cut

sub export_hash()
{   my %h = %{$_[0]->_record};
    delete $h{id};
    \%h;
}

=head2 $obj->delete;
Remove the related record from the database.
=cut

sub delete() { $_[0]->_record->delete }

=head2 $obj->update(\%update);
Change the database fields for the record.

As field names, you may either use the names is the record, or their renamed
versions.  The former are used in the web interface, the latter in other parts
of the program.  It's a bit tricky, but avoids accidents.  Renames should
disappear anyway...
=cut

sub update($)
{   my ($self, $update) = @_;
    my $rename = $self->db_field_rename;
    $update->{$_} = delete $update->{$rename->{$_}}
        for grep exists $update->{$rename->{$_}}, keys %rename;

    $self->_record->update($update);
}

=head2 my $obj_id = $class->create(\%insert);
Create a new record in the database, in the specific table.
=cut

sub create($)
{   my ($class, $create) = @_;
    my $rename = $class->db_field_rename;
    $create->{$_} = delete $create->{$rename->{$_}}
        for grep exists $create->{$rename->{$_}}, keys %rename;

    my $result = $::db->create($class->db_table, $create);
    $result->id;
}

1;
