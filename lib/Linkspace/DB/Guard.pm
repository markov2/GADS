
package Linkspace::DB::Guard;

use Log::Report 'linkspace';
use Devel::GlobalDestruction 'in_global_destruction';

# Implement nested guards via savepoints.  Normal nested transactions
# are not supported by Postgres, but savepoints are supported by most
# databases.  Savepoints are more flexible: they can clean-up any number
# of steps.

my $transaction;
my $savepoint_name = 'aaaa';

sub new($)
{   my ($class, $db) = @_;

    unless($transaction)
    {   return $transaction = $db->schema->storage->txn_scope_guard;
    }

    my $name = $savepoint_name++;
    $transaction->{dbh}->pg_savepoint($name);
    bless { savepoint => $name, active => 1 }, $class;
}

{ #XXX Why does the scope-guard not implement explicit rollback?
  use DBIx::Class::Storage::TxnScopeGuard;
  package DBIx::Class::Storage::TxnScopeGuard;
  sub rollback() {
     my $guard = $_[0];
     $guard->{storage}->txn_rollback;
     $guard->{inactivated} = 1;
     undef $_[0];   # try kill guard object from caller
   }
}

sub rollback()
{   my ($self) = @_;

    if(my $sp = $self->{savepoint})
    {   undef $_[0];   # attempt to remove external guard reference
        $self->{active} or return;

        $transaction->{dbh}->pg_rollback_to($sp);
        $self->{active} = 0;
    }
    elsif($transaction)
    {   $transaction->rollback;
        undef $transaction;
    }
    else { panic "Rollback without transaction" }
}

sub commit()
{   my ($self) = @_;

    if(my $sp = $self->{savepoint})
    {   undef $_[0];   # attempt to remove external guard reference
        $self->{active} or return;

        $transaction->{dbh}->pg_release($sp);
        $self->{active} = 0;
    }
    elsif($transaction)
    {   $transaction->commit;
        undef $transaction;
    }
    else { panic "Commit without transaction" }
}

sub DESTROY
{   my $self = shift;
    return if in_global_destruction;

    if($self->{savepoint})
    {   undef $_[0];   # attempt to remove external guard reference
        $self->rollback;
    }
    elsif($transaction)
    {   undef $transaction;
    }
}

1;
