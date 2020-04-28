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
    my $info   = $rclass->columns_info or panic "schema $rclass not loaded";

    my $rename = $class->db_field_rename;
    $rename->{instance_id} = 'sheet_id' if $info->{instance_id};

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
use Data::Dumper;
        *{"${class}::$attr"} = eval <<__ACCESSOR;
sub { \@_==1 or error "Read-only accessor ${class}::$attr"; \$_[0]{_coldata}{$acc} }
__ACCESSOR
    }

    foreach my $acc (keys %$rename)
    {   next if $class->can($acc);  # some other implementation of the method
        *{"${class}::$acc"} = eval <<__RENAME;
sub { error "Accessor ${class}::$acc renamed to $rename->{$acc}" }
__RENAME
    }
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

# This attribute shall not be used outside the object which manages the table:
# always use clean abstraction to address the fields.
has _record => (
	is       => 'ro',
    required => 1,
    trigger  => sub { $_[0]{_coldata} = $_[1]{_column_data} },
);

=head2 my $column = $obj->column($which);
Many objects address columns: to simplify access it got an efficient call.  When
the object relates to a sheet, that C<columns()> is called which prefers local
names when they are used.  Otherwise, the lookup is in the site wide column index.
=cut

# Cache the looked-up function address which translates column ids/name into
# column objects.
has _get_column => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        ( $self->has_sheet || $self->can('sheet_id')
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
    is        => 'lazy',
    weakref   => 1,
    predicate => 1,
    builder   => sub
    {   $_[0]->_record->can('sheet_id') or panic "Object has no sheet";
        $::session->site->sheet($_[0]->sheet_id);
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
Change the database fields for the record.  Read about field rewrite rules below.
=cut

sub update($)
{   my ($self, $update) = @_;
    $self->_record->update($self->_record_converter->($update));
}

=head2 my $obj_id = $class->create(\%insert);
Create a new record in the database, in the specific table.  Read about field
rewrite rules below.
=cut

sub create($)
{   my ($class, $create) = @_;
    my $result = $::db->create($class->db_table, $class->_record_converter->($create));
    $result->id;
}

#------------------
=head1 EXPLAIN record conversion
In the original GADS code, it is sometimes hard to see whether a field is a
boolean, contains JSON, or contains an id.  Over time, there may be a database
rename projects, but for the moment, we solve this by mapping better (internal)
names to the problematic database (external) names.

(Renamed) field names which end on C<_id> expect and integer id, refering to
an object.  The same name without C<_id> can also be used: but in that case you
can also provide an object which id is automatically taken.

(Renamed) field names which end on C<_json> can be used with either a HASH
or a JSON string.  Yoy may also use the name without C<_json> with the same
result.

(Renamed) field names which start with C<is_>, C<can_>, C<do_>, or C<has_>
are treated as booleans.  Trues values become 1, false values become 0.
So: no need for "$condition ? 0 : 1" anymore.
=cut

sub _record_converter
{   my $thing  = shift;
    my $class  = ref $thing || $thing;
    my $info   = $class->db_result_class->columns_info;
    my $unused = $class->db_fields_unused;
    my $rename = $class->db_field_rename;
    $rename->{instance_id} = 'sheet_id' if $info->{instance_id};

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
    {   if($ext =~ /(.*)_id$/)
        {   $run{$1}    ||= $make->($int, 'blessed $_[0] ? $_[0]->id : $_[0]');
            $run{$ext}  ||= $make->($int, '$_[0]');
        }
        elsif($ext =~ /^(?:is|can|do|has)_/)
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
        ($run{$_} or panic "Unusable $_")->(delete $in->{$_}, $out)
            for grep exists $in->{$_}, keys %$in;
        $out;
    };

    no strict 'refs';
    *{"${class}::_record_converter"} = sub { $converter };
    $converter;
}

1;