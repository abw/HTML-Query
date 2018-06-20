use strict;
use warnings;
use lib qw( ./lib ../lib );
use HTML::TreeBuilder;
use Badger::Filesystem '$Bin Dir';
use Badger::Test
    tests => 2,
    debug => 'HTML::Query',
    args  => \@ARGV;

use HTML::Query 'Query';

our $Query    = 'HTML::Query';
our $Builder  = 'HTML::TreeBuilder';
our $test_dir = Dir($Bin);
our $html_dir = $test_dir->dir('html')->must_exist;
our $table = $html_dir->file('invalid_table.html')->must_exist;

my ($query, $tree);

#-----------------------------------------------------------------------
#
# Invalid HTML structure should be correctly validated by dependent library
# For example in invalid_table.html there is lacking tr in thead. It should
# be added by library like HTML::HTML5::Parser
#
# Github issue
# > https://github.com/abw/HTML-Query/issues/8
#
# Stack overflow question
# > https://stackoverflow.com/questions/50378204/how-htmlquery-autocomplete-invalid-html-in-perl-5/50378804#50378804
#
#-----------------------------------------------------------------------

$tree = $Builder->new;
$tree->parse_file( $table->absolute );
$query = Query $tree;

my $tr = $query->query('tr')->first->as_trimmed_text;
my $tbody = $query->query('tbody')->first->as_trimmed_text;

is( $tr, 'ABC');
is( $tbody, 'EFG');
