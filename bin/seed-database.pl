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

my $namespace = $ENV{CDB_NAMESPACE};

GetOptions (
    'initial_username=s' => \(my $initial_username),
    'sheet_name=s'       => \(my $sheet_name),
    'site'               => \(my $host),
) or exit;

my ($dbic) = values %{config->{plugins}->{DBIC}}
    or die "Please create config.yml before running this script";

unless ($sheet_name)
{   say "Please enter the name of the first datasheet";
    chomp ($sheet_name = <STDIN>);
}

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

my $guard = $::db->begin_work;

say qq(Creating site "$host");
my $site = Linkspace::Site->create({
    hostname                   => $host,
    register_organisation_name => 'Organisation',
});

say qq(Creating initial username "$initial_username" with all permisisons);
my $users = $site->users;
my $user  = $users->user_create({
    email       => $initial_username,
    permissions => $users->all_permissions,
});

say "Creating initial sheet '$sheet_name'";

my $sheet = $site->document->sheet_create({ name => $sheet_name });

$guard->commit;
