#!/usr/bin/env perl

# Test to assess bug reported by tnt [...] netsafe.cz
#
# https://rt.cpan.org/Public/Bug/Display.html?id=62100
#

use strict;
use warnings;
use HTML::Query;

use Badger::Test
    tests => 4,
    debug => 'HTML::Query',
    args  => \@ARGV;

my $doc = HTML::Query->new(text => '<p id="1" class="a">A</p>'.'<p id="2" class="b">B</p>');

my $result1 = $doc->query('p');
is( $result1->size, 2, 'two p elements in query' ); 
warn $result1->as_trimmed_text();
is( join(', ', $result1->as_trimmed_text()), 'A, B', 'proper elements returned' );

my $result2 = $result1->query('.b');
is( $result2->size, 1, 'one p element in query' ); 
is( join(', ', $result2->as_trimmed_text), 'B', 'proper element returned' ); 
