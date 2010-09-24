#! /usr/local/bin/perl
use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

my %opts = (
    'NAME'         => 'HTML-Query',
    'VERSION_FROM' => 'lib/HTML/Query.pm',
    'PMLIBDIRS'    => [ 'lib' ],
    'PREREQ_PM'    => {
        'HTML::Tree'  => 3.23,
        'Badger'      => 0.03,
    },
    'dist'         => {
	PREOP => 'pod2text lib/HTML/Query.pm > README',
    },
    'test'         => {
        'TESTS'    => join(' ', map { glob } qw( t/*.t )),
    },
);

# Handle dev versions in our check
my $mmv = $ExtUtils::MakeMaker::VERSION;
$mmv =~ s/\_.+//;

if ($mmv >= 5.43) {
#    $opts{ AUTHOR   } = 'Andy Wardley <abw@wardley.org>';
    $opts{ AUTHOR   } = 'Kevin Kamel <kamelkev@mailermailer.com>';
    $opts{ ABSTRACT } = 'perform jQuery-like queries on HTML::Element trees',
}

if ($ExtUtils::MakeMaker::VERSION ge '6.30_00') {
    $opts{'LICENSE' } = 'perl';
}

WriteMakefile( %opts );

