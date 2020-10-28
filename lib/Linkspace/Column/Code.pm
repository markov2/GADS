## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

# Shared by ::Calc and ::Rag
package Linkspace::Column::Code;

use Log::Report        'linkspace';
use DateTime;
use Date::Holidays::GB qw/is_gb_holiday gb_holidays/;
use List::Utils        qw/uniq/;

use Linkspace::Util    qw/index_by_id/;
use linkspace::Column::Code::DependsOn;

use Moo;
extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub has_cache      { 1 }
sub is_userinput   { 0 }

###
### Class
###

###
### Instance
###

has depends_on => (
    is      => 'lazy',
    builder => sub { Linkspace::Column::Code::DependsOn->new(column => $_[0]) },
);

# Ignores field in Layout record  #XXX
sub can_child { $_[0]->depends_on->count }

use Inline 'Lua' => q{
    function lua_run(string, vars, working_days_diff, working_days_add)
        local env = {}
        env["vars"] = vars

        env["working_days_diff"] = working_days_diff
        env["working_days_add"] = working_days_add

        env["ipairs"] = ipairs
        env["math"] = {
            abs = math.abs,
            acos = math.acos,
            asin = math.asin,
            atan = math.atan,
            atan2 = math.atan2,
            ceil = math.ceil,
            cos = math.cos,
            cosh = math.cosh,
            deg = math.deg,
            exp = math.exp,
            floor = math.floor,
            fmod = math.fmod,
            frexp = math.frexp,
            huge = math.huge,
            ldexp = math.ldexp,
            log = math.log,
            log10 = math.log10,
            max = math.max,
            min = math.min,
            modf = math.modf,
            pi = math.pi,
            pow = math.pow,
            rad = math.rad,
            random = math.random,
            sin = math.sin,
            sinh = math.sinh,
            sqrt = math.sqrt,
            tan = math.tan,
            tanh = math.tanh
        }
        env["next"] = next
        env["os"] = {
            clock = os.clock,
            date = os.date,
            difftime = os.difftime,
            time = os.time
        }
        env["pairs"] = pairs
        env["pcall"] = pcall
        env["select"] = select
        env["string"] = {
            byte = string.byte,
            char = string.char,
            find = string.find,
            format = string.format,
            gmatch = string.gmatch,
            gsub = string.gsub,
            len = string.len,
            lower = string.lower,
            match = string.match,
            rep = string.rep,
            reverse = string.reverse,
            sub = string.sub,
            upper = string.upper
        }
        env["table"] = {
            insert = table.insert,
            maxn = table.maxn,
            remove = table.remove,
            sort = table.sort
        }
        env["tonumber"] = tonumber
        env["tostring"] = tostring
        env["type"] = type
        env["unpack"] = unpack

        func, err = load(string, nil, 't', env)
        ret = {}
        if err then
            ret["success"] = 0
            ret["error"] = err
            return ret
        end
        ret["success"] = 1
        ret["return"] = func()
        return ret
    end
};

has code => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my $code = $self->_rset_code && $self->_rset_code->code;
        $code || '';
    },
);

has write_cache => (
    is      => 'rw',
    default => 1,
);

sub params
{   my $self = shift;
    $self->_params_from_code($self->code);
}

sub param_columns
{   my ($self, %options) = @_;
    my $sheet_id = $self->sheet_id;

    grep $_, map {
        my $col = $self->column($_)
            or error __x"Unknown short column name '{name}' in calculation", name => $_;

        $col->sheet_id == $sheet_id
            or error __x"It is only possible to use fields from sheet ({sheet1}). '{name}' is from {sheet2}.",
                name => $_, sheet1 => $self->sheet->name, sheet2 => $col->sheet->name;
        $col;
    } $self->params;
}

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

sub _params_from_code
{   my ($self, $code) = @_;
    my $params = $self->_parse_code($code)->{params};
    @$params;
}

sub _parse_code
{   my ($self, $code) = @_;
    !$code || $code =~ /^\s*function\s+evaluate\s*\(([A-Za-z0-9_,\s]+)\)(.*?)end\s*$/s
        or error "Invalid code definition: must contain function evaluate(...)";

    +{
        code   => $2,
        params => [ $1 ? (split /[,\s]+/, $1) : () ],
     };
}

sub _is_workday($$)
{   my ($dt, $region) = @_;
    return 0 if $dt->day_of_week >= 6;  # Sat or Sun

    is_gb_holiday year => $dt->year, month => $dt->month, day => $dt->day,
        regions => [ $region ];
}

# XXX These functions can raise exceptions - further investigation needed as to
# whether this causes problems when called from Lua. Initial experience
# suggests it might do.
sub working_days_diff
{   my ($start_epoch, $end_epoch, $country, $region) = @_;

    $country eq 'GB' or error "Only country GB is currently supported";
    $start_epoch     or error "Start date missing for working_days_diff";
    $end_epoch       or error "End date missing for working_days_diff";

    my $start = DateTime->from_epoch(epoch => $start_epoch);
    my $end   = DateTime->from_epoch(epoch => $end_epoch);

    # Check that we have the holidays for the years requested
    my $min = $start < $end ? $start->year : $end->year;
    my $max = $end > $start ? $end->year : $start->year;

    foreach my $year ($min..$max)
    {   error __x"No bank holiday information available for year {year}", year => $year
            if !%{gb_holidays(year => $year, regions => [$region])};
    }

    my $workdays = 0;
    if($end > $start)
    {   my $marker = $start->clone->add(days => 1);
        while($marker <= $end)
        {   $workdays++ if _is_workday $marker, $region;
            $marker->add(days => 1);
        }
    }
    else
    {   my $marker = $start->clone->subtract(days => 1);
        while($marker >= $end)
        {   $workdays-- if _is_workday $marker, $region;
            $marker->subtract(days => 1);
        }
    }

    $workdays;
}

sub working_days_add
{   my ($start_epoch, $days, $country, $region) = @_;

    $country eq 'GB' or error "Only country GB is currently supported";
    $start_epoch or error "Date missing for working_days_add";

    my $start = DateTime->from_epoch(epoch => $start_epoch);

    error __x"No bank holiday information available for year {year}", year => $start->year
        if !%{gb_holidays(year => $start->year, regions => [$region])};

    while($days)
    {   $start->add(days => 1);
	    $days-- if _is_workday $start, $region;
    }

    $start->epoch;
}

sub eval
{   my ($self, $code, $vars) = @_;
    my $run_code = $self->_parse_code($code)->{code};
    my $mapping = '';
    $mapping .= qq($_ = vars["$_"]\n) foreach keys %$vars;
    $run_code = $mapping.$run_code;
    my $return = lua_run($run_code, $vars, \&working_days_diff, \&working_days_add);
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
        return => $ret,
        error  => $err,
        code   => $run_code,
    }
}

sub write_special
{   my ($self, %options) = @_;

    my $id   = $options{id};
    my $rset = $options{rset};

    # rset_code may have been built before the rset property had been
    # initialised
    $self->_clear_rset_code;
    my $new = !$id || !$self->_rset_code->code;

    # It is not uncommon for users to accidentally copy auto-corrected
    # characters such as "smart quotes". These then result in a rather vague
    # Lua error about invalid char values. Instead, let's disallow all extended
    # characters, and give the user a sensible error.
    $self->code =~ /(.....[^\x00-\x7F]+.....)/
        and error __x"Extended characters are not supported in calculated fields (found here: {here})",
            here => $1;

    my %return_options;
    my $changed = $self->write_code($id, %options); # Returns true if anything relevant changed

    if($options{update_dependents} || $changed)
    {   $return_options{no_alerts} = 1 if $new;
        my @depends_on = grep !$_->is_internal,
            $self->param_columns(is_fatal => $options{override} ? 0 : 1);

        $self->depends_on->set_dependencies(\@depends_on);
    }
    else
    {   $return_options{no_cache_update} = 1;
    }
    %return_options;
}

# We don't really want to do this within a transaction as it can take a
# significantly long time, so do once the transaction has completed
sub after_write_special
{   my ($self, %options) = @_;
    $self->update_cached(no_alerts => $options{no_alerts})
        unless $options{no_cache_update};
}

1;
