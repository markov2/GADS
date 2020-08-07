=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

use warnings;
use strict;

package Linkspace::Util;
use parent 'Exporter';

our @EXPORT_OK = qw/
    flat
    is_valid_email
    index_by_id
    iso2datetime
    is_valid_id
    list_diff
    make_wordlist
    parse_duration
    scan_for_plugins
    uniq_objects
/;

use DateTime::Format::ISO8601   ();
use DateTime::Format::DateManip ();

use Scalar::Util  qw(weaken);
use List::Util    qw(first);
use File::Glob    qw(bsd_glob);

=head1 NAME
Linkspace::Util - collection of useful functions

=head1 SYNOPSIS
  # You have to import all functions explicitly
  use Linkspace::Util qw(iso2datetime);

=head1 DESCRIPTION
Collections of functions used all over the place.  Sometimes it is hard
to decide whether some code should be in a function or as method to an
object.  Keep it simple!

=head1 FUNCTIONS

=head2 my @values = flat \@array|$value, ...
Flatten a LIST into values.  It will not go into nested ARRAYs.  An C<undef>
single value will result in an empty return, but C<undefs> in the array will
be kept.
=cut

sub flat(@) {
    map { ref $_ eq 'ARRAY' ? @$_ : defined $_ ? $_ : () } @_;
}

=head2 is_valid_email $email or die;
Returns a true value when a C<user@domain.tld> string is passed: not a full
RFC2822 email address.
=cut

# Noddy email address validator. Not much point trying to be too clever here.
# We don't use Email::Valid, as that will check for RFC822 address as opposed
# to pure email address on its own.

sub is_valid_email($)
{   $_[0] =~ m/^[=+\'a-z0-9._-]+\@[a-z0-9.-]+\.[a-z]{2,10}$/i;
}

=head2 my $index = index_by_id @objects;

=head2 my $index = index_by_id \@objects;
Create a HASH which maps ids to their objects.  This is used very ofter to
speed-up access to objects by id reference.

B<WARNING>: When you produce an index which contains foreign objects, do
not forget to weaken those relations.  Otherwise, you may leak in a loop.
=cut

sub index_by_id(@)
{   +{ map +($_->id => $_), flat @_ };
}

=head2 my $dt = iso2datetime $string;
Convert a date represented as ISO8601 string to a L<DateTime> object.
=cut

sub iso2datetime($)
{   my $stamp = shift or return;
    DateTime::Format::ISO8601->parse_datetime($stamp);
}


=head2 my $is_valid = is_valid_id $string;
Returns the database 'id', which is always numeric and larger than zero.
Surrounding blanks are skipped.  For 
=cut

sub is_valid_id($)
{   defined $_[0] && $_[0] =~ /^\s*([0-9]+)\s*$/ && $1 != 0 ? $1 : undef;
}

=head2 my $duration = parse_duration $string;
Returns a L<DateTime::Duration> object.
=cut

sub parse_duration($) { DateTime::Format::DateManip->parse_duration($_[0]) }


=head2 my $plugins = scan_for_plugins $subpkg, %options;
Search the C<@INC> path (set by 'use lib' and the PERL5LIB environment
variable) for files which seem to contain plugins of a certain group.

It is a pity that there is no assurance that implementers are not
enforced to have matching package names and file names in Perl.  Gladly,
nearly everyone does it right automatically.

The scan will get all modules which match C<lib/Linkspace/$subpkg/*.pm>.

Example:

  my $pkgs_hash = scan_for_plugins 'Command', load => 1;
  # Will load  Linkspace::Commmand::Install  when it exists.

=cut

sub scan_for_plugins($%) {
    my ($subspace, %args) = @_;
    my $namespace = "Linkspace::$subspace";
    my $subpath   = $namespace =~ s!\:\:!/!gr;

   my $autoload   = $args{load};

    my %pkgs;
    foreach my $inc (@INC) {
        ref $inc && next;    # ignore code refs

        foreach my $filename (bsd_glob "$inc/$subpath/[!_]*.pm") {

            my $pkg = $filename =~ s!.*\Q$inc/!!r =~ s!\.pm$!!r =~ s!/!::!gr;
            next if $pkgs{$pkg};

            $pkgs{$pkg} = $filename;
            $autoload or next;

            (my $plugin_base = $filename) =~ s!^\Q$inc/\E!!;
            my $has = first { /\Q$plugin_base\E$/ } keys %INC;
            next if $has;

            eval "use $pkg (); 1"
                or die "ERROR: failed to load plugin $pkg from $filename:\n$@";
        }
    }

    \%pkgs;
}

=head2 my @subset = uniq_objects @objects;
=head2 my @subset = uniq_objects \@objects;
De-duplicate objects, based on their id.  Maintains order.
=cut

sub uniq_objects
{   my %seen;
    grep ! $seen{$_->id}++, flat @_;
}
 
=head2 my ($added, $deleted, $both) = list_diff $from, $to;
Returns three ARRAYs, which contain the changes in between ARRAYs C<$from>
and C<$to>.  The order in the returned arrays is unspecified.
=cut

sub list_diff($$)
{   my ($from, $to) = @_;
    my %from = map +($_ => 1), @{$from || []};
    my %to   = map +($_ => 1), @{$to   || []};
    my @both = grep exists $to{$_}, keys %from;
    delete @from{@both};
    delete @to{@both};
    ( [ keys %to ], [ keys %from ], \@both);
}

=head2 my $string = make_wordlist @words;
Show a humanly readible list of alternatives, like a list of names.  The
words are separated by a comma-blank, except the last one, which is
preceeded by 'and'.  Returns an empty string when there are no words.
May also be called with an array.
=cut

sub make_wordlist(@)
{   my @words = flat @_;
    return '' if !@words;
    return $words[0] if @words==1;

    my $final = pop @words;
    join(', ', @words) . " and $final";
}

1;
