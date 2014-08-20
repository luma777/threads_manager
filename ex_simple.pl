#/usr/bin/env perl

##
##  SIMPLE THREAD
##

use strict;
use warnings;
use threads::manager;

my $max_threads = 10;

my $tm = threads::manager->new( $max_threads );

for (0..50) {
	my $param = $_;
	$tm->create(\&my_sub_thread, $param)
}

$tm->wait_all_threads;

## Sub threaded
sub my_sub_thread {
	my ($val) = @_;
	printf("Finish val: %s\n", $val);
}