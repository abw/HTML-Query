#============================================================= -*-perl-*-
#
# t/universal.t
#
# Test script for the query() method.
#
# Written by Chelsea Rio/Kevin Kamel, September 24, 2010
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use HTML::TreeBuilder;
use Badger::Filesystem '$Bin Dir';
use Badger::Test
    tests => 23,
    debug => 'HTML::Query',
    args  => \@ARGV;

use HTML::Query 'Query';

our $Query    = 'HTML::Query';
our $Builder  = 'HTML::TreeBuilder';
our $test_dir = Dir($Bin);
our $html_dir = $test_dir->dir('html')->must_exist;
our $universal = $html_dir->file('universal.html')->must_exist;

my ($query, $tree);

#-----------------------------------------------------------------------
# load up second test file and create an HTML::Query object for it.
#-----------------------------------------------------------------------

$tree = $Builder->new;
$tree->parse_file( $universal->absolute );
ok( $tree, 'parsed tree for second test file: ' . $universal->name );
$query = Query $tree;
ok( $query, 'created query' );

#-----------------------------------------------------------------------
# look for some basic elements using duplicate tagnames in query
#-----------------------------------------------------------------------

my $test0 = $query->query('div.danger *');
ok( $test0, 'div.danger *' );
is( $test0->size, 4, 'div.danger *' ); #includes javascript and metas
is( join(', ', $test0->as_trimmed_text), '(div class="green") (div class="yellow") (div class="danger") (div class="green")(/div) (/div) (/div) (/div), (div class="yellow") (div class="danger") (div class="green")(/div) (/div) (/div), (div class="danger") (div class="green")(/div) (/div), (div class="green")(/div)','got var' );

my $test1 = $query->query('div.green');
ok( $test1, 'div.green' );
is( $test1->size, 2, 'div.green' );
is( join(', ', $test1->as_trimmed_text), '(div class="green") (div class="yellow") (div class="danger") (div class="green")(/div) (/div) (/div) (/div), (div class="green")(/div)','got var' );

my $test2 = $query->query('div.yellow');
ok( $test2, 'div.yellow' );
is( $test2->size, 1, 'div.yellow' );
is( join(', ', $test2->as_trimmed_text), '(div class="yellow") (div class="danger") (div class="green")(/div) (/div) (/div)','got var' );

my $test3 = $query->query('div.danger * [class="green"]');
ok( $test3, 'div.danger * [class="green"]' );
is( $test3->size, 1, 'div.danger * [class="green"]' );
is( join(', ', $test3->as_trimmed_text), '(div class="green")(/div)','got var' );

my $test4 = $query->query('div.danger *[class="green"]');
ok( $test4, 'div.danger *[class="green"]' );
is( $test4->size, 2, 'div.danger *[class="green"]' );
is( join(', ', $test4->as_trimmed_text), '(div class="green") (div class="yellow") (div class="danger") (div class="green")(/div) (/div) (/div) (/div), (div class="green")(/div)','got var' );

my $test5 = $query->query('div.danger * *[class="green"]');
ok( $test5, 'div.danger * *[class="green"]' );
is( $test5->size, 1, 'div.danger * *[class="green"]' );
is( join(', ', $test5->as_trimmed_text), '(div class="green")(/div)','got var' );

my $test6 = $query->query('div.danger * * *[class="green"]');
ok( $test6, 'div.danger * * *[class="green"]' );
is( $test6->size, 1, 'div.danger * * *[class="green"]' );
is( join(', ', $test6->as_trimmed_text), '(div class="green")(/div)','got var' );

