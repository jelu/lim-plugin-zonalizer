package Lim::Plugin::Zonalizer;

use common::sense;

use base qw(Exporter Lim::Component);

our @EXPORT_OK = qw(ERR_DUPLICATE_ID ERR_ID_NOT_FOUND ERR_REVISION_MISSMATCH
  ERR_INVALID_LIMIT ERR_INVALID_SORT_FIELD ERR_INTERNAL_DATABASE
  ERR_INVALID_AFTER ERR_INVALID_BEFORE
  STATUS_QUEUED STATUS_ANALYZING STATUS_DONE STATUS_FAILED STATUS_STOPPED
  STATUS_UNKNOWN
  );
our %EXPORT_TAGS = (
    err => [
        qw(ERR_DUPLICATE_ID ERR_ID_NOT_FOUND ERR_REVISION_MISSMATCH
           ERR_INVALID_LIMIT ERR_INVALID_SORT_FIELD ERR_INTERNAL_DATABASE
           ERR_INVALID_AFTER ERR_INVALID_BEFORE)
    ],
    status => [
        qw(STATUS_QUEUED STATUS_ANALYZING STATUS_DONE STATUS_FAILED
           STATUS_STOPPED STATUS_UNKNOWN)
    ]
);

=encoding utf8

=head1 NAME

Lim::Plugin::Zonalizer - Analyze your zones with ZoneMaster

=head1 VERSION

Version 0.10

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

  use Lim::Plugin::Zonalizer;

  # Create a Server object
  $server = Lim::Plugin::Zonalizer->Server;

  # Create a Client object
  $client = Lim::Plugin::Zonalizer->Client;

  # Create a CLI object
  $cli = Lim::Plugin::Zonalizer->CLI;

=head1 DESCRIPTION

...

=head1 ERRORS

  use Lim::Plugin::Zonalizer qw(:err);

See API documentation for full description about errors.

=over 4

=item ERR_DUPLICATE_ID

=item ERR_ID_NOT_FOUND

=item ERR_REVISION_MISSMATCH

=item ERR_INVALID_LIMIT

=item ERR_INVALID_SORT_FIELD

=item ERR_INTERNAL_DATABASE

=item ERR_INVALID_AFTER

=item ERR_INVALID_BEFORE

=back

=cut

sub ERR_DUPLICATE_ID()       { return 'duplicate_id_found' }
sub ERR_ID_NOT_FOUND()       { return 'id_not_found' }
sub ERR_REVISION_MISSMATCH() { return 'revision_missmatch' }
sub ERR_INVALID_LIMIT()      { return 'invalid_limit' }
sub ERR_INVALID_SORT_FIELD() { return 'invalid_sort_field' }
sub ERR_INTERNAL_DATABASE()  { return 'internal_database_error' }
sub ERR_INVALID_AFTER()      { return 'invalid_after' }
sub ERR_INVALID_BEFORE()     { return 'invalid_before' }

=head1 STATUSES

  use Lim::Plugin::Zonalizer qw(:status);

See API documentation for full description about statuses.

=over 4

=item STATUS_QUEUED

=item STATUS_ANALYZING

=item STATUS_DONE

=item STATUS_FAILED

=item STATUS_STOPPED

=item STATUS_UNKNOWN

=back

=cut

sub STATUS_QUEUED()    { return 'queued' }
sub STATUS_ANALYZING() { return 'analyzing' }
sub STATUS_DONE()      { return 'done' }
sub STATUS_FAILED()    { return 'failed' }
sub STATUS_STOPPED()   { return 'stopped' }
sub STATUS_UNKNOWN()   { return 'unknown' }

=head1 METHODS

=over 4

=item $plugin_name = Lim::Plugin::Zonalizer->Name

Returns the plugin's name.

=cut

sub Name {
    'Zonalizer';
}

=item $plugin_description = Lim::Plugin::Zonalizer->Description

Returns the plugin's description.

=cut

sub Description {
    'Analyze your zones with ZoneMaster.';
}

=item $call_hash_ref = Lim::Plugin::Zonalizer->Calls

Returns a hash reference to the calls that can be made to this plugin, used both
in Server and Client to verify input and output arguments.

See CALLS for list of calls and arguments.

=cut

sub Calls {
    {
        Read1 => {
            uri_map => [
                'version => ReadVersion version=1',
                'status => ReadStatus version=1',
                'analysis => ReadAnalysis version=1',
                'analysis/id=[\w-]+ => ReadAnalyze version=1',
                'analysis/id=[\w-]+/status => ReadAnalyzeStatus version=1'
            ]
        },
        Create1 => {
            uri_map => [
                'analysis => CreateAnalyze version=1'
            ]
        },
        Update1 => {
            uri_map => []
        },
        Delete1 => {
            uri_map => [
                'analysis => DeleteAnalysis version=1',
                'analysis/id=[\w-]+ => DeleteAnalyze version=1'
            ]
        },

        ReadVersion => {
            in => { version => 'string' },
            out => { version => 'string' }
        },

        ReadStatus => {
            in => { version => 'string' },
            out => {
                api => {
                    requests => 'integer',
                    errors => 'integer'
                },
                analysis => {
                    ongoing => 'integer',
                    completed => 'integer',
                    failed => 'integer'
                }
            }
        },

        ReadAnalysis => {
            in => {
                version   => 'integer',
                ongoing   => 'integer optional',
                results   => 'integer optional',
                lang      => 'string optional',
                limit     => 'integer optional',
                before    => 'string optional',
                after     => 'string optional',
                sort      => 'string optional',
                direction => 'string optional',
                base_url  => 'integer optional'
            },
            out => {
                analysis => {
                    id       => 'string',
                    url      => 'string',
                    fqdn     => 'string',
                    status   => 'string',
                    error    => {
                        code    => 'string',
                        message => 'string'
                    },
                    progress => 'integer',
                    created  => 'integer',
                    updated  => 'integer',
                    results  => {
                        _id => 'integer',
                        args => { '' => 'swallow' },
                        level => 'string',
                        module => 'string',
                        tag => 'string',
                        timestamp => 'integer',
                        message => 'string'
                    },
                    summary  => {
                        '' => 'single',
                        notice => 'integer',
                        warning => 'integer',
                        error => 'integer',
                        critical => 'integer'
                    },
                    ipv4 => 'integer',
                    ipv6 => 'integer'
                },
                paging => {
                    ''      => 'single',
                    cursors => {
                        ''     => 'required single',
                        after  => 'string',
                        before => 'string'
                    },
                    previous => 'string optional',
                    next     => 'string optional'
                }
            }
        },
        DeleteAnalysis => {
            in => {
                version => 'integer'
            }
        },

        CreateAnalyze => {
            in  => {
                version => 'integer',
                fqdn => 'string',
                ipv4 => 'integer optional',
                ipv6 => 'integer optional'
            },
            out => { id   => 'string' }
        },
        ReadAnalyze => {
            in => {
                version => 'integer',
                id => 'string',
                results => 'integer optional',
                lang => 'string optional',
                last_results => 'integer optional'
            },
            out => {
                id       => 'string',
                url      => 'string',
                fqdn     => 'string',
                status   => 'string',
                error    => {
                    code    => 'string',
                    message => 'string'
                },
                progress => 'integer',
                created  => 'integer',
                updated  => 'integer',
                results  => {
                    _id => 'integer',
                    args => { '' => 'swallow' },
                    level => 'string',
                    module => 'string',
                    tag => 'string',
                    timestamp => 'integer',
                    message => 'string'
                },
                summary  => {
                    '' => 'single',
                    notice => 'integer',
                    warning => 'integer',
                    error => 'integer',
                    critical => 'integer'
                },
                ipv4 => 'integer',
                ipv6 => 'integer'
            }
        },
        ReadAnalyzeStatus => {
            in => {
                version => 'integer',
                id => 'string',
            },
            out => {
                status   => 'string',
                progress => 'integer',
                updated  => 'integer'
            }
        },
        DeleteAnalyze => {
            in => {
                version => 'integer',
                id => 'string'
            }
        }
    };
}

=item $command_hash_ref = Lim::Plugin::Zonalizer->Commands

Returns a hash reference to the CLI commands that can be made by this plugin.

See COMMANDS for list of commands and arguments.

=cut

sub Commands {
    {};
}

=back

=head1 CALLS

See L<Lim::Component::Client> on how calls and callback functions should be
used.

=head1 COMMANDS

...

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry@gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-zonalizer/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Zonalizer

You can also look for information at:

=over 4

=item * Lim issue tracker (report bugs here)

L<https://github.com/jelu/lim-plugin-zonalizer/issues>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2015 Jerry Lundström
Copyright 2015 IIS (The Internet Foundation in Sweden)

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Lim::Plugin::Zonalizer
