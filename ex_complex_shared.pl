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

for ( 1 .. 10 ) {
    my $param = $_;
    $tm->create( { timeout => 10 }, 'my_sub_thread', $param );
}

## wait threads
$tm->wait_all_threads;

## attention key3 and key4
print Dumper $myHash;

## Sub threaded
sub my_sub_thread {
    my ($val) = @_;
    push @{ $myHash->{count} }, $val;

    my $newKey = 'key' . $val;
    $myHash->add( { $newKey => [$val] } );
}

