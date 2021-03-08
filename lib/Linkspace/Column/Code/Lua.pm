## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Code::Lua;
use parent 'Exporter';

use utf8;
use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Util    qw(index_by_id working_days_diff working_days_add);

our @EXPORT_OK = qw(lua_run lua_parse lua_validate);

use Inline Lua => <<'__WRAPPER';
    function lua_wrapper(string, vars, working_days_diff, working_days_add)
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
__WRAPPER

sub lua_run($$)
{   my ($run_code, $vars) = @_;

    my $mapping = join "\n", map qq($_ = vars["$_"]), keys %$vars;

    lua_wrapper("$mapping\n$run_code", $vars, \&working_days_diff, \&working_days_add);
}

sub lua_parse($)
{   my $code = shift or return (undef, []);

    # The code is already validated.
    my ($params, $run_code) = $code =~ /^\s*function\s+evaluate\s*\(([\w\s,]*)\)(.*?)end\s*$/s;
    ($run_code, [ split /[,\s]+/, $params ]);
}

sub lua_validate($$)
{   my ($sheet, $code) = @_;

    $code =~ /^\s*function\s+evaluate\s*\([\w\s,]*\).*?end\s*$/s
        or error "Invalid code: must contain function evaluate(...)";

    # It is not uncommon for users to accidentally copy auto-corrected
    # characters such as "smart quotes". These then result in a rather vague
    # Lua error about invalid char values. Instead, let's disallow all extended
    # characters, and give the user a sensible error.
    $code =~ /(.....[^\x00-\x7F]+.....)/
        and error __x"Extended characters are not supported in calculated fields (found here: {here})",
           here => $1;

     my ($run_code, $params) = lua_parse $code;
     my $layout = $sheet->layout;

     foreach my $param (@$params)
     {   my $column = $layout->column($param)
             or error __x"Unknown short column name '{name}' in calculation", name => $param;

         $column->sheet_id == $sheet->id
             or error __x"It is only possible to use columns from sheet {sheet1.name}; '{name}' is on {sheet2.name}.",
                name => $param, sheet1 => $sheet, sheet2 => $column->sheet;
     }
}

1;
