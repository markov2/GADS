=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

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

package Linkspace::Mailer;

use Log::Report 'linkspace';
use Mail::Message;
use Mail::Message::Body::String;
use Mail::Transport::Sendmail;
use Text::Autoformat qw(autoformat break_wrap);

use Moo;

has message_prefix => (
    is       => 'ro',
    required => 1,
);

has email_from => (
    is       => 'ro',
    required => 1,
);

has new_account => (   #XXX???
    is       => 'ro',
);

sub send
{   my $self = @_;
    my $args = @_ > 1 ? +{ @_ } : shift;

    my $emails   = $args->{emails}
        or error __"Please specify some recipients to send an email to";

    my $subject  = $args->{subject}
        or error __"Please enter a subject for the email";

    my $reply_to = $args->{reply_to};

    my @parts;

    push @parts, Mail::Message::Body::String->new(
        mime_type   => 'text/plain',
        disposition => 'inline',
        data        => autoformat($args->{text}, {all => 1, break=>break_wrap}),
    ) if $args->{text};

    push @parts, Mail::Message::Body::String->new(
        mime_type   => 'text/html',
        disposition => 'inline',
        data        => $args->{html},
    ) if $args->{html};

    @parts or panic "No plain or HTML email text supplied";

    my $content_type = @parts > 1 ? 'multipart/alternative' : $parts[0]->type;

    my $msg = Mail::Message->build(
        Subject        => $subject,
        From           => $self->email_from,
        'Content-Type' => $content_type,
        attach         => \@parts,
    );
    $msg->head->add('Reply-to' => $reply_to) if $reply_to;

    # Start a mailer
    my $mailer = Mail::Transport::Sendmail->new;

    my %done;
    foreach my $email (@$emails)
    {   next if $done{$email}++; # Stop duplicate emails

        $msg->head->set(to => $email);
        $mailer->send($msg);
    }
}

sub message
{   my ($self, %args) = @_;

    my @emails;
    my $user = $::session->user;

    if ($args{records} && $args{col_id})
    {   foreach my $record (@{$args{records}->results})
        {   my $email = $record->fields->{$args{col_id}}->email;
            push @emails, $email if $email;
        }
    }

    push @emails, @{$args{emails}}
        if $args{emails};

    @emails or return;

    my $text = $args{text} =~ s/\s+$//r;
    $text = $self->message_prefix
          . $text
          . "\n\nMessage sent by: "
          . ($user->value||"")." (".$user->email.")\n";

    $self->send(
        subject  => $args{subject},
        emails   => \@emails,
        text     => $text,
        reply_to => $user->email,
    );
}

sub send_welcome($)
{   my ($self, %args) = @_;

    my $site = $::session->site;
    my $body = $site->email_welcome_text;

    my $url  = $::session->request->base . "resetpw/$args{code}";
    $body    =~ s/\Q[URL]/$url/;
    $body    =~ s/\Q[NAME]/$site->name/e;

    my $html = text2html(
        $body,
        lines     => 1,
        urls      => 1,
        email     => 1,
        metachars => 1,
    );

    $self->send(
        subject => $site->email_welcome_subject,
        text    => $body,
        html    => $html,
        emails  => [ $args{email} ],
    );
}

sub send_victim_rejected($)
{   my ($self, $victim) = @_;
    my $site = $::session->site;

    $self->send(
        subject => $site->email_reject_subject || 'Account request rejected',
        emails  => [ $victim->email ],
        text    => $site->email_reject_text || 'Your account request has been rejected.',
    );
}

sub send_victim_deleted($)
{   my ($self, $victim) = @_;
    my $site = $::session->site;
    my $msg = $site->email_delete_text or return;

    $self->send(
        subject => $site->email_delete_subject || "Account deleted",
        emails  => [ $victim->email ],
        text    => $msg,
    );
}

sub send_account_requested($$)
{   my ($self, $victim, $to) = @_;

    my $summary = $victim->summary;
    my $notes   = $victim->account_request_notes;
    my $text    = <<__EMAIL;
A new account request has been received from the following person:

$summary

User notes: $notes
__EMAIL

    $self->send(
        subject => 'New account request',
        emails  => $to,
        text    => $text,
    );
}

1;

