#============================================================= -*-perl-*-
#
# t/query.t
#
# Test script for the query() method.
#
# Written by Kevin Kamel, October 2010
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use HTML::TreeBuilder;
use Badger::Filesystem '$Bin Dir';
use Badger::Test
    tests => 63,
    debug => 'HTML::Query',
    args  => \@ARGV;

use HTML::Query 'Query';

our $Query    = 'HTML::Query';
our $Builder  = 'HTML::TreeBuilder';
our $test_dir = Dir($Bin);
our $html_dir = $test_dir->dir('html')->must_exist;
our $test3    = $html_dir->file('test3.html')->must_exist;

my ($query, $tree);

#-----------------------------------------------------------------------
# load up first test file and create an HTML::Query object for it.
#-----------------------------------------------------------------------

$tree = $Builder->new;
$tree->parse_file( $test3->absolute );
ok( $tree, 'parsed tree for first test file: ' . $test3->name );
$query = Query $tree;
ok( $query, 'created query' );

#-----------------------------------------------------------------------
# validate that multi class operands work
#-----------------------------------------------------------------------

my $stacked = $query->query('.bar.new-class');
is( $stacked->size, 2, 'found all elements with class ".bar.new-class"' );
is( join(', ', $stacked->as_trimmed_text), 'This is another div with bar class, This is a span with bar class','got correct stacked result' );

my $switchstacked = $query->query('.new-class.bar');
is( $switchstacked->size, 2, 'found all elements with class ".new-class.new-bar"' );
is( join(', ', $switchstacked->as_trimmed_text), 'This is another div with bar class, This is a span with bar class','got correct stacked result' );

my $tagclass = $query->query('span.bar.new-class');
is( $tagclass->size(), 1, 'found all elements with class "span.bar.new-class"' );
is( join(', ', $tagclass->as_trimmed_text), 'This is a span with bar class', 'got correct stacked result' );

my $switchtagclass = $query->query('span.new-class.bar');
is( $switchtagclass->size(), 1, 'found all elements with class "span.new-class.bar"' );
is( join(', ', $switchtagclass->as_trimmed_text), 'This is a span with bar class', 'got correct stacked result' );

#-----------------------------------------------------------------------
# validate that class/id operands work
#-----------------------------------------------------------------------



#-----------------------------------------------------------------------
# validate that class/attribute operands work
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# validate that id/attribute operands work
#-----------------------------------------------------------------------


#-----------------------------------------------------------------------
# validate that class/attribute/id operands work
#-----------------------------------------------------------------------

