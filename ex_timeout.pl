#/usr/bin/env perl

##
##  COMPLEX THREAD SHARED VARIABLES
##

use strict;
use warnings;
use threads::manager;
use Data::Dumper;

## myHash shared struct
my $myHash : SharedHash;

## using method add
$myHash->add(
    {   count => [],
        key1  => 'val1',
        key2  => 2,
        key3  => ['val3'],
        key4  => { others => 'keys' }
    }
);

## instance class
my $max_threads = 10;
my $tm          = threads::manager->new($max_threads);
my %ids = ();

for ( 1 .. 10 ) {
    my $param = $_;
    my $id = $tm->create( { timeout => 5 }, 'my_sub_thread', $param );
    $ids{ $id } = $param;
}

## wait threads
$tm->wait_all_threads;

printf("Threads KILL: %s\n", join(',', $tm->kill_ids));

## Sub threaded
sub my_sub_thread {
    my ($val) = @_;
    my $time = int(rand(20));
    print ($val." ".$time.$/);
    sleep $time;
}

