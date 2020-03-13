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
    {   my $attr = $rename{$acc} || $acc;
        *{"${class}::$attr"} = eval <<__ACCESSOR;
sub { \@_==1 or panic "read-only accessor ${class}::$attr"; \$_[0]->_record->$acc }
__ACCESSOR
    }
}

# To be overwritten
sub db_table        { panic "no \$db_table in $_[0]" }
sub db_result_class { 'GADS::Schema::Result::' . $_[0]->db_table }

# You may want to use different names for some accessors than used by the
# database.  Of course, it would be better to change the database field names
# themselves, but that's quite some effort.  Explicitly: rename all fields which
# accidentally lack a _id but are numeric identifiers.
sub db_field_rename { +{} }

#-----------------------
=head1 METHODS: Constructors

=head2 my $object = $class->from_record($record, %options);
When you have a C<$record> from the right type (the result class of the table), this
gets wrapped into a full Linkspace object.  The C<%options> are the attributes
for the created object, processed Moo style.
=cut

sub from_record($%)
{   my ($class, $record) = (shift, shift);
    $record->isa($self->db_result_class) or panic "wrong record of type";
    $record ?  $class->new(@_, _record => $record) : undef;
}

=head2 my $object = $class->from_id($obj_id, %options);
Create the C<$object> which manages a database record.
=cut

sub from_id($%)
{   my ($class, $obj_id) = (shift, shift);
    my $record = $::db->get_record($self->db_table => $obj_id);
    $record ? $self->new(@_, _record => $record) : undef;
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

sub column($) { $_[0]->get_column->($_[1]) }

=head2 $obj->sheet;
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
        $::session->site->sheet($_[0]->sheet_id) } : undef;
    },
);

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

1;
