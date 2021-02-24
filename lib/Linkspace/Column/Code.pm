## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

# Shared by ::Calc and ::Rag
package Linkspace::Column::Code;

use Log::Report        'linkspace';

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

sub _validate($)
{   my ($thing, $update) = @_;
    $thing->SUPER::_validate($update);

    if(my $code = $update->{code})
    {   lua_validate $code;
    }

    $update;
}

has values_dirty => ( is => 'rw', default => 0 );

sub update_dependencies()
{   my $self = shift;
    $self->depends_on->set_dependencies($self->param_columns);
}

has depends_on => (
    is      => 'lazy',
    builder => sub { Linkspace::Column::Code::DependsOn->new(column => $_[0]) },
);

# Ignores field in Layout record  #XXX
sub can_child { $_[0]->depends_on->count }

has _parsed_code => ( is => 'lazy', builder => sub { lua_parse $_[0]->code } );

sub param_names { $_[0]->_parsed_code->[1] }

sub param_columns
{   my ($self, %options) = @_;
    my $sheet_id = $self->sheet_id;

    [ grep defined && length, map {
        my $col = $self->column($_)
            or error __x"Unknown short column name '{name}' in calculation", name => $_;

        $col->sheet_id == $sheet_id
            or error __x"It is only possible to use fields from sheet ({sheet1.name}); '{name}' is from {sheet2.name}.",
                name => $_, sheet1 => $self->sheet, sheet2 => $col->sheet;
        $col;
    } $self->param_names ];
}

# XXX These functions can raise exceptions - further investigation needed as to
# whether this causes problems when called from Lua. Initial experience
# suggests it might do.

sub evaluate
{   my ($self, $code, $vars) = @_;
    my $run_code = $self->_parse_code->[0];
    my $return   = lua_run $run_code, $vars;

    # Make sure we're not returning anything funky (e.g. code refs)
    my $ret = $return->{return};

    if($self->is_multivalue && ref $ret eq 'ARRAY')
    {   $ret = [ map "$_", @$ret ];
    }
    elsif(defined $ret)
    {   $ret = "$ret";
    }

    my $err = $return->{error} && ''.$return->{error};
    no warnings "uninitialized";
    trace "Return value from Lua: $ret, error: $err";

    +{
        return => $ret,      # sometimes ARRAY sometimes scalar
        error  => $err,
        code   => $run_code,
    }
}


=pod

has write_cache => ( is => 'rw', default => 1 );

sub update_cached
{   my ($self, %args) = @_;

    return unless $self->write_cache;

    # $@ may be the result of a previous Log::Report::Dispatcher::Try block (as
    # an object) and may evaluate to an empty string. If so, txn_scope_guard
    # warns as such, so undefine to prevent the warning
    undef $@;

    $self->clear; # Refresh calc for updated calculation
    my $layout = $self->layout;
    my $sheet = $self->sheet;

    my $page = $sheet->content->search(
        columns              => [ @{$self->depends_on->columns}, $self ],
        view_limit_extra_id  => undef,
        curcommon_all_fields => 1, # Code might contain curcommon fields not in normal display
        include_children     => 1, # Update all child records regardless
    );

    my @changed;
    while(my $row = $page->next_row)
    {   my $cell = $row->cell($self);
        $datum->re_evaluate(no_errors => 1);
        $datum->write_value;
        push @changed, $row->current_id if $datum->changed;
    }

    my $alert = ! exists $args{send_alerts} || $args{send_alerts};
    $sheet->views->trigger_alerts(
        current_ids => \@changed,
        columns     => [ $self ],
    ) if $alert;

    \@changed;
}

=cut

1;
