#!/usr/bin/perl

use strict;
use warnings;

use Carp;
use Data::Dumper;

# These measurements are in percents.
use constant GREEN => 0.45;

use constant YELLOW => 0.80;

use constant RED => 1;

sub fgc {
	my ( $fh, $r );
	local $/ = undef;
	open $fh, '<', shift;
	$r = <$fh>;
	close $fh;
	return $r;
}

my ( $fh, @loadavg, $cpucount, $la );
$cpucount = 0;
@loadavg = split( ' ', fgc('/proc/loadavg') );

$/ = "\n\n";
open $fh, "</proc/cpuinfo";
<$fh> and $cpucount++ until eof $fh;
close $fh;

foreach ( 0..2 ) {
	$la = $loadavg[$_];
	$loadavg[$_] = "\033[32m$la\033[00m" if ( ($la / $cpucount >= 0 ) and ( $la / $cpucount <= GREEN ) );
	$loadavg[$_] = "\033[33m$la\033[00m" if ( ($la / $cpucount >= GREEN ) and ( $la / $cpucount <= YELLOW ) );
	$loadavg[$_] = "\033[31m$la\033[00m" if ( ($la / $cpucount >= YELLOW ) and ( $la / $cpucount <= RED ) );
	$loadavg[$_] = "\033[31;01m$la\033[00m" if ( $la / $cpucount > RED );
}

print join( ',', @loadavg[0..2] ) . "\n";
