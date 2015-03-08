#!/usr/bin/perl
use strict; 
use warnings; 
use LogInforSunhh; 


while (<>) {
	$. % 1e6 == 1 and &tsmsg("[Msg] Reading $. lines.\n");
	s/[^\S\t]+$//;
	my @ta = split(/\t/, $_);
	if ( $ta[0] eq 'chr' ) {
		print "$_\n";
		next;
	}
	my $base = uc($ta[2]);
	my $has_diff = 0;
	for (my $i=4; $i<@ta; $i++) {
		$ta[$i] = uc($ta[$i]);
		$ta[$i] eq 'N' and next;
		$base eq 'N' and $base = $ta[$i];
		$base ne $ta[$i] and do { $has_diff = 1; last; };
	}
	$has_diff == 1 and print "$_\n";
}