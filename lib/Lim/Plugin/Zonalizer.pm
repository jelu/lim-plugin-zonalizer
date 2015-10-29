package Lim::Plugin::Zonalizer;

use common::sense;

use base qw(Lim::Component);

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
                'analyze => ReadAnalyze version=1',
                'analyze/id=[\w-]+ => ReadAnalyze version=1'
            ]
        },
        Create1 => {
            uri_map => [
                'analyze => CreateAnalyze version=1'
            ]
        },
        Update1 => {
            uri_map => []
        },
        Delete1 => {
            uri_map => [
                'analyze => DeleteAnalyze version=1'
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
                version => 'integer',
                result => 'integer optional'
            },
            out => {
                analyze => {
                    id       => 'string',
                    zone     => 'string',
                    status   => 'string',
                    progress => 'integer',
                    created  => 'integer',
                    updated  => 'integer',
                    result   => { '' => 'swallow' }
                }
            }
        },

        CreateAnalyze => {
            in  => {
                version => 'integer',
                zone => 'string'
            },
            out => { id   => 'string' }
        },
        ReadAnalyze => {
            uri_map => [
                'id=[\w-]+ => ReadAnalyze'
            ],
            in => {
                version => 'integer',
                id => 'string',
                result => 'integer optional',
                last_result => 'integer optional'
            },
            out => {
                id       => 'string',
                zone     => 'string',
                status   => 'string',
                progress => 'integer',
                created  => 'integer',
                updated  => 'integer',
                result   => { '' => 'swallow' }
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
