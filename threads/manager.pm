package threads::manager;

use strict;
use threads ( 'yield', 'exit' => 'thread_only' );
use threads::shared;
use Scalar::Util 'looks_like_number';
use Attribute::Handlers;

our $VERSION = sprintf "%d.%d", q$Revision: 0.02 $ =~ /(\d+)/g;

my $timeout__            = 0;
my %tids__ : shared      = ();
my @tids_kill__ : shared = ();
my $lock__ : shared      = 0;

###############
## IMPORT  ###########
#################
##
## DESCRICAO: exporta funcoes para o programa
##
sub import {
    ## funcoes exportadas
    my @exp = qw/
        stop_semaphore
        start_semaphore
        threads::shared::shared_clone
        threads::shared::share
        threads::shared::is_shared
        /;

    my $call = caller;

    ## exportando funcoes
    foreach (@exp) {
        my $func = /.*::(.+)$/ ? $1 : $_;
        eval( '*' . $call . '::' . $func . '=\&$_' )
            or do {
            require Carp;
            Carp::croak( '"' . $_ . '" function not exported. ' . $@ );
            };
    }
}

#################
## ATTR Shared ########
####################
##
## DESCRICAO: Compartilhamento da variavel
##
sub UNIVERSAL::SharedHash : ATTR(ANY) {
    my $var  = $_[2];
    my $type = $_[4];
    my $ev   = '';
    my $obj  = {};

    bless( $obj, $_[0] );

    ## metodo add
    $ev = '*' . $_[0] . '::add = ';
    $ev .= q^
      sub
      {
         my $self = $_[0];
         my $data = $_[1];
         my $ov;

         unless(ref $data eq 'HASH')
         {
            $ov   = $data;
            $data = $_[2];
            unless ($ov eq 'override')
            {
               require Carp;
               Carp::croak('USE: my $data : SharedHash; $data->add(\'override\', {...});');
            }
         }

         unless(ref $data eq 'HASH')
         {
            require Carp;
            Carp::croak('USE: my $data : SharedHash; $data->add({...});');
         }
    ^;
    $ev
        .= 'while($'
        . $_[0]
        . '::lock_1_data){} $'
        . $_[0]
        . '::lock_1_data++;';
    $ev .= q^
         foreach (keys %{$data})
         {
            &decode(\$self->{$_}, $data->{$_}, $ov);
         }
   ^;
    $ev .= '$' . $_[0] . '::lock_1_data = 0;';
    $ev .= q^
         sub decode {
             my $self = $_[0];
             my $obj  = $_[1];
             my $ov   = $_[2];

             unless(ref $obj)
             {
                 $$self = $obj unless($$self and !$ov);
                 return;
             }
             
             if (ref $obj eq 'ARRAY')
             {
                 $$self = shared_clone([]) if $ov || !(ref $$self eq 'ARRAY');
                 for (0..(scalar(@{$obj}) - 1))
                 {
                     &decode($ov ? \$$self->[$_] : \$$self->[scalar(@{$$self})], $obj->[$_], $ov);
                 }
             }
             elsif (ref $obj eq 'HASH')
             {
                 $$self = shared_clone({}) unless(ref $$self eq 'HASH');
                 foreach(keys %{$obj})
                 {
                    &decode(\$$self->{$_}, $obj->{$_}, $ov);
                 };
             }
         }
      };
   ^;

    ## metodo clear
    $ev
        .= '*'
        . $_[0]
        . '::clear = sub { my $self = shift; delete $self->{$_} foreach (keys %{$self}); 1 };';

    ## var $lock_1_data (controla a escrita do objeto)
    $ev .= '$' . $_[0] . '::lock_1_data; share($' . $_[0] . '::lock_1_data);';

    ## construindo atributo
    eval($ev) or do { require Carp; Carp::croak( 'error: ' . $@ ) };

    ## Shared
    $$var = shared_clone($obj);
}

###########
## NEW  #############
##############
##
## DESCRICAO: Construtor
##
sub new {
    my ( $class, $self, $max, $arg, $th );

    $class = shift;
    ( $max, $arg ) = @_;

    ## Validando entrada de numero de threads
    unless ( looks_like_number($max) and int($max) == $max ) {
        require Carp;
        Carp::croak( 'USE: '
                . $/
                . 'my $max_threads = 10; '
                . $/
                . __PACKAGE__
                . '->new($max_threads)' );
    }

    ## Validando entrada de timeout
    if ( ref $arg eq 'HASH' and exists $arg->{'timeout'} ) {
        $timeout__ = $arg->{'timeout'};
        unless ( looks_like_number($timeout__)
            and int($timeout__) == $timeout__ )
        {
            require Carp;
            Carp::croak( 'USE: '
                    . $/
                    . __PACKAGE__
                    . '->new($max_threads, {timeout => 60})' );
        }
    }

    threads->yield();

    ## Criando thread de monitoracao das outras threads
    $th = threads->create('killThreads');
    select( undef, undef, undef, 0.025 );

    if ( !$th->is_running and !$th->is_joinable and !$th->is_detached ) {
        $th->join;
    }

    $self = {
        'max'      => $max + 1,
        'tidadmin' => $th->tid
    };

    bless( $self, $class );
}

#############
## CREATE  #########
###############
##
## DESCRICAO: Cria nova thread
##
## SYNTAX:
##
##       $pt->create(\&func, param_1, param_2, param_n);
##                      ou
##       $pt->create('func', param_1, param_2, param_n);
##
sub create {
    my ( $self, $func, $th, $tout );
    $self = shift;
    $func = shift;

    ## timeout para a thread
    if ( ref $func eq 'HASH' and looks_like_number( $func->{'timeout'} ) ) {
        $tout = $func->{'timeout'};
        $func = shift;
    }

    ## validando paramentro de func ref CODE
    unless ( ref $func eq 'CODE' ) {
        my $call = caller;
        unless ( $call->can($func) ) {
            require Carp;
            Carp::croak( '"' . $func . '" function not found!' );
        }

        eval( '$func=\&' . $call . '::' . $func )
            or do {
            require Carp;
            Carp::croak( 'error: ' . $@ );
            };
    }

    ## criando thread admin caso ela tenha terminado
    unless ( $self->{'tidadmin'} ) {
        $th = threads->create('killThreads');
        select( undef, undef, undef, 0.02 );
        if ( !$th->is_running and !$th->is_joinable and !$th->is_detached ) {
            $th->join;
        }

        $self->{'tidadmin'} = $th->tid;
        undef($th);
    }

    while (1) {
        ## Validando a quantidade de threads rodando
        if ( scalar( threads->list(threads::running) ) < $self->{'max'} ) {
            ## criando a thread
            $th = threads->create( $func, @_ );
            select( undef, undef, undef, 0.05 );

            ## executando a thread
            if (    !$th->is_running
                and !$th->is_joinable
                and !$th->is_detached )
            {
                $th->join;
            }

            $tids__{ $th->tid }
                = ( $tout || $timeout__ )
                ? time + ( $tout || $timeout__ )
                : 0;
            return $th->tid;
        }
        sleep 1;
    }
}

##########################
## WAIT ALL THREADS  ###############
###############################
##
## DESCRICAO: aguarda a execucao de todas as threads
##
## SYNTAX:
##          $pt->wait_all_threads;
##
sub wait_all_threads {
    my $self = shift;
    my @tids;

    while ( @tids = threads->list(threads::running) ) {
        foreach (@tids) {
            if ( scalar(@tids) == 1 and $_->tid == $self->{'tidadmin'} ) {
                $_->kill('KILL')->detach;
                $self->{'tidadmin'} = 0;
            }
        }
        sleep 1;
    }

    &__detach;
    1;
}

##################
## SEMAPHOFRES  ###############
########################
##
## DESCRICAO: Paraliza outras threads para execucao exclusiva
##
## SYNTAX:
##          sub {
##                my $var = shift;
##                start_semaphore;  ## para outras threads
##                $var++;
##                stop_semaphore;   ## libera execucao de outras threads
##                return;
##              }
##
sub start_semaphore {
    while ($lock__) { select( undef, undef, undef, 0.5 ) }
    $lock__++;
}
sub stop_semaphore { $lock__ = 0; 1; }

#####################
## KILL Threads  ##############
#########################
##
## DESCRICAO: Monitora os timeout das threads
##
sub killThreads {
    local $SIG{'KILL'} = sub {return};
    while (1) {
        foreach ( keys %tids__ ) {
            if ( $tids__{$_} and time > $tids__{$_} ) {
                my $th = threads->object($_);
                if ( eval { $th->is_running } or eval { $th->is_joinable } ) {
                    $th->kill('KILL');
                    push @tids_kill__, $_;
                    delete $tids__{$_};
                    select( undef, undef, undef, 0.5 );
                }
            }
        }
        sleep 1;

        ## descarrega therads ja finalizadas
        &__detach;
    }
}

sub kill_ids {
    return @tids_kill__;
}

#################
## DETACH  ##############
###################
##
## DESCRICAO: descarrega threads que ja finalizaram
##
## SYNTAX: metodo interno
##
sub __detach {
    foreach ( threads->list(threads::joinable) ) {
                $_->detach
            and $_->kill('KILL')
            and $_->exit
            and delete $tids__{ $_->tid };
    }
    1;
}

1;

__END__

   
   
   
   

