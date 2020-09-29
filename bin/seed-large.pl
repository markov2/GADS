#!/usr/bin/perl

=pod
GADS - Globally Accessible Data Store
Copyright (C) 2015 Ctrl O Ltd

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

use strict;
use warnings;
use 5.10.0;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use Dancer2;
use Dancer2::Plugin::DBIC;
use DBIx::Class::Migration;

use GADS::Config;
use Linkspace::Layout;
use GADS::Group;
use GADS::Column::String;
use GADS::Column::Intgr;
use GADS::Column::Enum;
use GADS::Column::Tree;

# Seed singleton
GADS::Config->instance(
    config => config,
);

my ($initial_username, $host);
GetOptions (
    'initial_username=s' => \$initial_username,
    'site'               => \$host,
) or exit;

my ($dbic) = values %{config->{plugins}{DBIC}}
    or die "Please create config.yml before running this script";

unless ($initial_username)
{   say "Please enter the email address of the first user";
    chomp ($initial_username = <STDIN>);
}

unless ($host)
{   say "Please enter the hostname that will be used to access this site";
    chomp ($host = <STDIN>);
}

my $migration = DBIx::Class::Migration->new(
    schema_class => 'GADS::Schema',
    schema_args  => [{
        user         => $dbic->{user},
        password     => $dbic->{password},
        dsn          => $dbic->{dsn},
        quote_names  => 1,
    }],
);

say "Installing schema...";
$migration->install;

say "Inserting permissions fixtures...";
$migration->populate('permissions');

# It's possible that permissions may not have been populated.  DBIC Migration
# doesn't error if the fixtures above don't exist, and whenever a new version
# of the schema is created, the fixtures need to be copied across, which needs
# to be done manually. So, at least do a check now:
rset('Permission')->count
    or die "No permissions populated. Do the fixtures exist?";

say "Creating site '$host';
my $site = rset('Site')->create({
    host                       => $host,
    register_organisation_name => 'Organisation',
});

schema->site_id($site->id);

say "Creating initial username '$initial_username'";
my @all_global_permissions = map $_->name, @{$site->users->global_permissions};

my $user = $site->users->user_create({
    email       => $initial_username,
    permissions => $site->users->permission_shorts,
});

my $group  = $site->groups->group_create({ name => 'Read/write' });
$site->groups->group_add_user($group, $user);

my $perms = { $group->id =>
    [qw/read write_existing write_existing_no_approval write_new write_new_no_approval/]
};

my $activities = _create_sheet("Activities", string => 50, tree => 5, enum => 50, intgr => 50);

for my $i (1..10)
{
    my $curval_sheet = _create_sheet("Curval$i", string => 3, tree => 0, enum => 3, intgr => 1);
    my $curval_layout = $curval_sheet->layout;

    my $curval = $curval_layout->create_column(curval => {
        name             => "curval$i",
        is_optional      => 1,
        delete_not_used  => 1,
        show_add         => 1,
        value_selector   => 'noshow',
        permissions      => $perms,
        refers_to_sheet  => $curval_sheet,
        curval_columns   => $curval_layout->search_columns(exclude_internal => 1),
    });
}

sub _create_sheet
{   my ($name, %counts) = @_;

    say "Creating table $name";

    my $sheet  = $site->document->create_sheet({name => $name});
    my $layout = $sheet->layout;

    say "... creating $counts{string} string fields";
    for my $i (1..$counts{string})
    {   $layout->create_column(string => {
            name        => "string$i",
            is_optional => 1,
            permissions => $perms,
         });
    }

    say "... creating $counts{tree} tree fields";
    for my $i (1..$counts{tree})
    {    my @nodes = map +{ text => "Node $i $j", children => [] }, 1..200;
         $layout->create_column(tree => {
            name        => "tree$i",
            is_optional => 1,
            permissions => $perms,
            nodes       => \@nodes,
         });

    }

    say "... creating $counts{enum} enum fields";
    for my $i (1..$counts{enum})
    {   $layout->create_column(enum => {
            name        => "enum$1",
            is_optional => 1,
            permissions => $perms,
            enumvals    => [ map +{ value => "foo$j" }, 1..100 ],
         });
    }

    say "... creating $counts{intgr} integer fields";
    for my $i (1..$counts{intgr})
    {   $layout->create_column(intgr => {
            name        => "integer$i",
            is_optional => 1,
            permissions => $perms,
        });
    }

    $sheet;
}

