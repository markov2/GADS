## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Website::SubmissionToken;
use base 'Exporter';

use Log::Report  'linkspace';
use DateTime  ();

our @EXPORT = qw/create_submission_token consume_submission_token/;

=head1 NAME

Linkspace::Website::SubmissionToken - maintain unique tokens

=head1 SYNOPSIS

  my $token = create_submission_token;
  consume_submission_token $token;

=head1 DESCRIPTION

To keep the user from submitting the same information twice (by accidental
double click, for instance), we can hand-out tokens inside the forms.
Only the first who grabs te token from the database will get the right
to change the information.

=head1 FUNCTION

=head2 my $token = create_submisison_token;
=cut

sub create_submission_token()
{   for (1..10)
    {   # Prevent infinite loops in case something is really wrong with the
        # system (token collisions are implausible)
        my $token = Session::Token->new(length => 32)->get;
        try { $::db->create(Submission => { created => DateTime->now, token => $token }) };
        return $token unless $@;
    }
    undef;
}

=head2 consume_submission_token $token;
=cut

sub consume_submission_token($)
{   my $token = shift;

    my $sub = $::db->search(Submission => {token => $token})->first;
    $sub or return;  # Should always be found, but who knows

    # The submission table has a unique constraint on the token and
    # submitted cells. If we have already been submitted, then we
    # won't be able to write a new submitted version of this token, and
    # the record insert will therefore fail.
    try {
        $::db->create(Submission => {
            token     => $token,
            created   => DateTime->now,
            submitted => 1,
        });
    };

    if($@)
    {   # borked, assume that the token has already been submitted
        error __"This form has already been submitted and is currently being processed";
    }
}

1;
