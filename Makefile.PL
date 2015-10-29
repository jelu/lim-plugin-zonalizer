use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Lim::Plugin::Zonalizer',
    AUTHOR              => q{Jerry Lundström <lundstrom.jerry@gmail.com>},
    VERSION_FROM        => 'lib/Lim/Plugin/Zonalizer.pm',
    ABSTRACT_FROM       => 'lib/Lim/Plugin/Zonalizer.pm',
    (! eval { ExtUtils::MakeMaker->VERSION(6.3002) } ? () :
        (LICENSE => 'perl')
    ),
    (eval { ExtUtils::MakeMaker->VERSION(6.5503) } ?
    (
        BUILD_REQUIRES => {
            'Test::More' => 0,
            'common::sense' => 3,
            'Lim' => 0.16,
            'Getopt::Long' => 2.38,
            'Scalar::Util' => 1,
            'URI::Escape::XS' => 0.11,
            'OSSP::uuid' => 0,
            'Clone' => 0,
            'AnyEvent::CouchDB' => 1.31,
            'AnyEvent::HTTP' => 2.21,
            'JSON' => 0,
            'HTTP::Status' => 0,
            'JSON::XS' => 0,
        },
        PREREQ_PM => {
            'common::sense' => 3,
            'Lim' => 0.16,
            'Getopt::Long' => 2.38,
            'Scalar::Util' => 1,
            'URI::Escape::XS' => 0.11,
            'OSSP::uuid' => 0,
            'Clone' => 0,
            'AnyEvent::CouchDB' => 1.31,
            'AnyEvent::HTTP' => 2.21,
            'JSON' => 0,
            'HTTP::Status' => 0,
            'JSON::XS' => 0,
        }
    ) : (
        PREREQ_PM => {
            'Test::More' => 0,
            'common::sense' => 3,
            'Lim' => 0.16,
            'Getopt::Long' => 2.38,
            'Scalar::Util' => 1,
            'URI::Escape::XS' => 0.11,
            'OSSP::uuid' => 0,
            'Clone' => 0,
            'AnyEvent::CouchDB' => 1.31,
            'AnyEvent::HTTP' => 2.21,
            'JSON' => 0,
            'HTTP::Status' => 0,
            'JSON::XS' => 0,
        }
    )),
    (! eval { ExtUtils::MakeMaker->VERSION(6.46) } ? () :
        (META_ADD => {
            resources => {
                homepage   => 'https://github.com/jelu/lim-plugin-zonalizer',
                repository => 'https://github.com/jelu/lim-plugin-zonalizer',
                bugtracker => 'https://github.com/jelu/lim-plugin-zonalizer/issues',
            },
        })
    ),
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Lim-Plugin-Zonalizer-*' },
);