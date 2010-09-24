#! /usr/local/bin/perl
use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

my %opts = (
    'NAME'         => 'HTML-Query',
    'VERSION'      => '0.02',
    'PMLIBDIRS'    => [ 'lib' ],
    'PREREQ_PM'    => {
        'HTML::Tree'  => 3.23,
        'Badger'      => 0.03,
    },
    'dist'         => {
        'COMPRESS' => 'gzip',
        'SUFFIX'   => 'gz',
    },
    'test'         => {
        'TESTS'    => join(' ', map { glob } qw( t/*.t )),
    },
);

# Handle dev versions in our check
my $mmv = $ExtUtils::MakeMaker::VERSION;
$mmv =~ s/\_.+//;

if ($mmv >= 5.43) {
    $opts{ AUTHOR   } = 'Andy Wardley <abw@wardley.org>';
    $opts{ ABSTRACT } = 'perform jQuery-like queries on HTML::Element trees',
}

if ($ExtUtils::MakeMaker::VERSION ge '6.30_00') {
    $opts{'LICENSE' } = 'perl';
}

WriteMakefile( %opts );

