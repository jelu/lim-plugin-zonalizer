package Lim::Plugin::Zonalizer::Server;

use common::sense;

use Scalar::Util qw(weaken);

use Lim::Plugin::Zonalizer ();

use Lim::Util ();

use OSSP::uuid       ();
use MIME::Base64     ();
use AnyEvent         ();
use AnyEvent::Handle ();
use JSON::XS         ();

use base qw(Lim::Component::Server);

=encoding utf8

=head1 NAME

Lim::Plugin::Zonalizer::Server - Server class for the zonalizer Lim plugin

=head1 VERSION

See L<Lim::Plugin::Zonalizer> for version.

=cut

our $VERSION = $Lim::Plugin::Zonalizer::VERSION;

our %STAT    = (
    api => {
        requests => 0,
        errors   => 0
    },
    tests => {
        ongoing => 0,
        completed => 0,
        failed => 0
    }
);
our %TEST;

=head1 SYNOPSIS

  use Lim::Plugin::Zonalizer;

  # Create a Server object
  $server = Lim::Plugin::Zonalizer->Server;

=head1 METHODS

These methods are called from the Lim framework and should not be used else
where.

Please see L<Lim::Plugin::Zonalizer> for full documentation of calls.

=over 4

=item Init

=cut

sub Init {
    my ( $self ) = @_;
    my $real_self = $self;
    weaken( $self );

    $self->{cleaner} = AnyEvent->timer(after => 60, interval => 60, cb => sub {
        unless ( $self ) {
            return;
        }

        foreach (values %TEST) {
            if ($_->{updated} < (time - 600)) {
                delete $TEST{$_->{id}};
            }
        }
    });
}

=item Read1

=cut

sub Read1 {
    my ( $self, $cb ) = @_;
    $STAT{api}->{requests}++;

    #
    # This call is only used to map to other calls and should not be called
    # directly so return an error if anyone does.
    #

    $STAT{api}->{errors}++;
    $self->Error( $cb );
    return;
}

=item Create1

=cut

sub Create1 {
    my ( $self, $cb ) = @_;
    $STAT{api}->{requests}++;

    #
    # This call is only used to map to other calls and should not be called
    # directly so return an error if anyone does.
    #

    $STAT{api}->{errors}++;
    $self->Error( $cb );
    return;
}

=item Update1

=cut

sub Update1 {
    my ( $self, $cb ) = @_;
    $STAT{api}->{requests}++;

    #
    # This call is only used to map to other calls and should not be called
    # directly so return an error if anyone does.
    #

    $STAT{api}->{errors}++;
    $self->Error( $cb );
    return;
}

=item Delete1

=cut

sub Delete1 {
    my ( $self, $cb ) = @_;
    $STAT{api}->{requests}++;

    #
    # This call is only used to map to other calls and should not be called
    # directly so return an error if anyone does.
    #

    $STAT{api}->{errors}++;
    $self->Error( $cb );
    return;
}

=item ReadVersion

=cut

sub ReadVersion {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    $self->Successful( $cb, { version => $VERSION } );
    return;
}

=item ReadStatus

=cut

sub ReadStatus {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    $self->Successful( $cb, \%STAT );
    return;
}

=item ReadAnalysis

=cut

sub ReadAnalysis {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    my @analysis;

    foreach ( sort { $b->{update} <=> $a->{update} } values %TEST ) {
        my $analyze = {
            %{$_}
        };

        unless ( $q->{result} ) {
            delete $analyze->{result};
        }

        push( @analysis, $analyze );

        if ( scalar @analysis == 10 ) {
            last;
        }
    }

    $self->Successful( $cb, { analyze => \@analysis } );
    return;
}

=item CreateAnalyze

=cut

sub CreateAnalyze {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    my $uuid = OSSP::uuid->new;
    $uuid->make( 'v4' );
    my $id = MIME::Base64::encode_base64url( $uuid->export( "bin" ) );

    $TEST{$id} = {
        id       => $id,
        zone     => $q->{zone},
        status   => 'analyzing',
        progress => 0,
        created  => time,
        updated  => time
    };

    my $cli;
    unless ( open( $cli, '-|:encoding(UTF-8)', 'zonemaster-cli', qw(--json_stream --json_translate --no-ipv6 --level DEBUG), $q->{zone} ) ) {
        $STAT{tests}->{failed}++;
        $self->Error( $cb, 'no' );
        return;
    }

    $STAT{tests}->{ongoing}++;

    my $json         = JSON::XS->new->utf8;
    my $modules      = 0;
    my $modules_done = 0;
    my $started      = 0;
    my $result_id    = 0;
    my $handle;
    my $failed = sub {
        $STAT{tests}->{ongoing}--;
        $STAT{tests}->{failed}++;
    };
    $handle = AnyEvent::Handle->new(
        fh      => $cli,
        on_read => sub {
            my ( $handle ) = @_;

            unless ( defined $self ) {
                return;
            }

            if ( $handle->destroyed ) {
                $TEST{$id}->{progress} = 100;
                delete $TEST{$id}->{result};
                if ( defined $failed ) {
                    $failed->();
                    undef $failed;
                }
                return;
            }

            my $error;
            eval {
                my @msg = $json->incr_parse( $handle->{rbuf} );
                foreach my $msg ( @msg ) {
                    unless ( ref( $msg ) eq 'HASH' ) {
                        die;
                    }

                    $TEST{$id}->{updated} = time;

                    if ( $msg->{level} eq 'DEBUG' || ( $msg->{level} eq 'INFO' && $msg->{tag} eq 'POLICY_DISABLED' ) ) {
                        if ( !$started && $msg->{tag} eq 'MODULE_VERSION' ) {
                            $modules++;
                        }
                        elsif ( $msg->{tag} eq 'MODULE_END' || $msg->{tag} eq 'POLICY_DISABLED' ) {
                            $started = 1;
                            $modules_done++;

                            $TEST{$id}->{progress} = ( $modules_done * 100 ) / $modules;

                            $self->{logger}->debug( 'done ', $modules_done, ' progress ', $TEST{$id}->{progress} );
                        }
                    }

                    if ( $msg->{level} eq 'DEBUG' ) {
                        next;
                    }

                    $msg->{_id} = $result_id++;
                    push( @{ $TEST{$id}->{result} }, $msg );
                }
            };
            if ( $@ ) {
                $TEST{$id}->{progress} = 100;
                delete $TEST{$id}->{result};
                $handle->destroy;
                $handle = undef;
                if ( defined $failed ) {
                    $failed->();
                    undef $failed;
                }
                return;
            }
            $handle->{rbuf} = '';
        },
        on_eof => sub {
            unless ( defined $self ) {
                return;
            }

            $TEST{$id}->{progress} = 100;
            if ( defined $failed ) {
                $STAT{tests}->{ongoing}--;
                $STAT{tests}->{completed}++;
                undef $failed;
            }
            if ( $handle->destroyed ) {
                delete $TEST{$id}->{result};
                return;
            }

            $handle->destroy;
            $handle = undef;
        },
        on_error => sub {
            my ( undef, undef, $message ) = @_;

            unless ( defined $self ) {
                return;
            }

            $TEST{$id}->{progress} = 100;
            delete $TEST{$id}->{result};
            if ( defined $failed ) {
                $failed->();
                undef $failed;
            }
            if ( $handle->destroyed ) {
                return;
            }

            $handle->destroy;
            $handle = undef;
        }
    );

    $self->Successful( $cb, { id => $id } );
    return;
}

=item ReadAnalyze

=cut

sub ReadAnalyze {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    unless ( exists $TEST{ $q->{id} } ) {
        $self->Error( $cb, 'not found' );
        return;
    }

    if ( exists $q->{result} and !$q->{result} ) {
        my %test = %{ $TEST{ $q->{id} } };
        delete $test{result};
        $self->Successful( $cb, \%test );
        return;
    }

    if ( exists $q->{last_result} and $q->{last_result} ) {
        my %test = %{ $TEST{ $q->{id} } };
        my $result = delete $test{result};
        $test{result} = scalar @$result < $q->{last_result} ? [ @$result ] : [ @{$result}[-$q->{last_result}..-1] ];
        $self->Successful( $cb, \%test );
        return;
    }

    $self->Successful( $cb, $TEST{ $q->{id} } );
    return;
}

=item DeleteAnalyze

=cut

sub DeleteAnalyze {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    unless ( exists $TEST{ $q->{id} } ) {
        $self->Error( $cb, 'not found' );
        return;
    }

    delete $TEST{ $q->{id} };

    $self->Successful( $cb );
    return;
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry@gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<http://your.bugtracker.com/lim-plugin-zonalizer>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Zonalizer

You can also look for information at:

=over 4

=item * Lim issue tracker (report bugs here)

L<http://your.bugtracker.com/lim-plugin-zonalizer>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2015 Jerry Lundström.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Lim::Plugin::Zonalizer::Server
