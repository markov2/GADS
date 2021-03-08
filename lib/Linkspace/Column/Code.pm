## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

# Shared by ::Calc and ::Rag
package Linkspace::Column::Code;

use Log::Report    'linkspace';
use Data::Dumper   qw/Dumper/;

use Linkspace::Column::Code::DependsOn ();
use Linkspace::Column::Code::Lua qw(lua_run lua_parse lua_validate);

use Moo;
extends 'Linkspace::Column';

### 2021-02-22: columns in GADS::Schema::Result::LayoutDepend
# id         depends_on layout_id

###
### META
###

sub has_cache      { 1 }
sub is_userinput   { 0 }

###
### Class
###

###
### Instance
###

sub _validate($$)
{   my ($thing, $update, $sheet) = @_;

    if(my $code = $update->{code})
    {   lua_validate $sheet, $code;
    }

    $thing->SUPER::_validate($update, $sheet);
    $update;
}

sub update_dependencies()
{   my $self = shift;
    $self->depends_on->set_dependencies($self->param_columns);
}

sub depends_on() { $_[0]->{LCC_dep} ||= Linkspace::Column::Code::DependsOn->new(column => $_[0]) };

# Ignores field in Layout record  #XXX ignore when???
sub can_child    { $_[0]->depends_on->count }

has _parsed_code => ( is => 'lazy', builder => sub { [ lua_parse $_[0]->code ] } );

sub param_names   { $_[0]->_parsed_code->[1] }
sub param_columns { $_[0]->{LCC_cols} ||= $_[0]->layout->columns($_[0]->param_names) }

=head2 \@datums = $column->initial_datums($revision);
When there are no datums for this cell, it may mean that the calculation still has
to start.  But we are waiting for it, so compute it now.  Actually, this is always
used to bootstrap computation, one way or another.
=cut

sub initial_datums($%)
{   my ($self, $revision) = @_;

    my $run_code = $self->_parsed_code->[0]
        or return;

    my %vars     = map +($_->name_short => $revision->cell($_)->for_code),
        @{$self->param_columns};

    my $result   = try { lua_run $run_code, \%vars };
    my $error    = $@ ? $@->wasFatal->message->toString : $result->{error};

    my $dc       = $self->datum_class;
    if($error)
    {   warning __x"Failed to eval code for field '{field}': {error} (code: {code}, params: {params})",
            field  => $self->name, error => $error,
            code   => $result->{code} || $self->code,
            params => Dumper(\%vars);

        return [ $dc->new_error(column => $self, value => 1, error => $error) ];
    }

    # Make sure we're not returning anything funky (e.g. code refs)
    my $raws   = $result->{return};
    my @raws   = map "$_", ref $raws eq 'ARRAY' ? @$raws : defined $raws ? $raws : ();
    trace "Return raw from Lua: @raws" if @raws;

    my @datums;
    foreach my $raw (@raws)
    {   my $value = try { $self->is_valid_value($raw) };
        push @datums, $@
          ? $dc->new_error($revision, $self, 2, $@->wasFatal->message->toString)
          : $dc->new_datum($revision, $self, $value);
    }

    \@datums;
}


=pod

    my $alert = ! exists $args{send_alerts} || $args{send_alerts};
    $sheet->views->trigger_alerts(
        current_ids => \@changed,
        columns     => [ $self ],
    ) if $alert;

    \@changed;
}

=cut

1;
