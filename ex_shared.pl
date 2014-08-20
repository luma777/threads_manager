#/usr/bin/env perl

##
##  SIMPLE THREAD SHARED VARIABLES
##

use strict;
use warnings;
use threads::manager;

my @var_shared : shared = ();

my $max_threads = 10;
my $tm = threads::manager->new( $max_threads );

for (0..50) {
	my $param = $_;
	$tm->create('my_sub_thread', $param)
}

$tm->wait_all_threads;

printf("Value of \@var_shared is: %s\n", join(",", @var_shared));

## Sub threaded
sub my_sub_thread {
	my ($val) = @_;
	push @var_shared, $val;
}