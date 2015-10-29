package Lim::Plugin::Zonalizer::Server;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);

use Lim::Plugin::Zonalizer qw(:err);

use Lim              ();
use Lim::Error       ();
use OSSP::uuid       ();
use MIME::Base64     ();
use AnyEvent         ();
use AnyEvent::Handle ();
use JSON::XS         ();
use HTTP::Status     ();

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
    analysis => {
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

    # Default configuration

    $self->{default_limit}     = 10;
    $self->{max_limit}         = 10;
    $self->{base_url}          = 1;
    $self->{db_driver}         = 'Memory';
    $self->{db_conf}           = {};

    # Load configuration

    if ( ref( Lim->Config->{zonalizer} ) eq 'HASH' ) {
        foreach ( qw(default_limit max_limit base_url db_driver custom_base_url) ) {
            if ( defined Lim->Config->{zonalizer}->{$_} ) {
                $self->{$_} = Lim->Config->{zonalizer}->{$_};
            }
        }

        if ( defined Lim->Config->{zonalizer}->{db_conf} ) {
            unless ( ref( Lim->Config->{zonalizer}->{db_conf} ) eq 'HASH' ) {
                confess "Configuration for db_conf is wrong, must be HASH";
            }

            $self->{db_conf} = Lim->Config->{zonalizer}->{db_conf};
        }
    }

    # Load database

    my $db_driver = 'Lim::Plugin::Zonalizer::DB::' . $self->{db_driver};
    eval 'use ' . $db_driver . ';';
    if ( $@ ) {
        confess $@;
    }
    $self->{db} = $db_driver->new( %{ $self->{db_conf} } );

    # Temporary memory scrubber

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
        my %test = %{$_};

        unless ( $q->{results} ) {
            delete $test{results};
        }

        push( @analysis, \%test );

        if ( scalar @analysis == 10 ) {
            last;
        }
    }

    $self->Successful( $cb, { analyze => \@analysis } );
    return;
}

=item DeleteAnalysis

=cut

sub DeleteAnalysis {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    %TEST = ();

    $self->Successful( $cb );
    return;
}

=item CreateAnalyze

=cut

sub CreateAnalyze {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    if ( $STAT{analysis}->{ongoing} > 1 ) {
        $self->Error(
            $cb,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_SERVICE_UNAVAILABLE,
                message => 'queue_full'
            )
        );
        return;
    }
    unless ( $q->{fqdn} =~ /^[a-zA-Z0-9\.-]+$/o ) {
        $self->Error(
            $cb,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_BAD_REQUEST,
                message => 'invalid_fqdn'
            )
        );
        return;
    }

    my $uuid = OSSP::uuid->new;
    $uuid->make( 'v4' );
    my $id = MIME::Base64::encode_base64url( $uuid->export( "bin" ) );

    my $test = $TEST{$id} = {
        id       => $id,
        fqdn     => $q->{fqdn},
        status   => 'analyzing',
        progress => 0,
        created  => time,
        updated  => time
    };

    my $cli;
    unless ( open( $cli, '-|:encoding(UTF-8)', 'zonemaster-cli', qw(--json_stream --json_translate --no-ipv6 --level DEBUG), $q->{fqdn} ) ) {
        $STAT{analysis}->{failed}++;
        $self->Error( $cb, 'no' );
        return;
    }

    $STAT{analysis}->{ongoing}++;

    my $json         = JSON::XS->new->utf8;
    my $modules      = 0;
    my $modules_done = 0;
    my $started      = 0;
    my $result_id    = 0;
    my $handle;
    my $failed = sub {
        $STAT{analysis}->{ongoing}--;
        $STAT{analysis}->{failed}++;
        $test->{status} = 'failed';
    };
    $handle = AnyEvent::Handle->new(
        fh      => $cli,
        on_read => sub {
            my ( $handle ) = @_;

            unless ( defined $self ) {
                return;
            }

            if ( $handle->destroyed ) {
                $test->{progress} = 100;
                delete $test->{results};
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

                    $test->{updated} = time;

                    if ( $msg->{level} eq 'DEBUG' || ( $msg->{level} eq 'INFO' && $msg->{tag} eq 'POLICY_DISABLED' ) ) {
                        if ( !$started && $msg->{tag} eq 'MODULE_VERSION' ) {
                            $modules++;
                        }
                        elsif ( $msg->{tag} eq 'MODULE_END' || $msg->{tag} eq 'POLICY_DISABLED' ) {
                            $started = 1;
                            $modules_done++;

                            $test->{progress} = ( $modules_done * 100 ) / $modules;

                            $self->{logger}->debug( 'done ', $modules_done, ' progress ', $test->{progress} );
                        }
                    }

                    if ( $msg->{level} eq 'DEBUG' ) {
                        next;
                    }

                    $msg->{_id} = $result_id++;
                    push( @{ $test->{results} }, $msg );
                }
            };
            if ( $@ ) {
                $test->{progress} = 100;
                delete $test->{results};
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

            $test->{progress} = 100;
            if ( defined $failed ) {
                $STAT{analysis}->{ongoing}--;
                $STAT{analysis}->{completed}++;
                $test->{status} = 'done';
                undef $failed;
            }
            if ( $handle->destroyed ) {
                delete $test->{results};
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

            $test->{progress} = 100;
            delete $test->{results};
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
        $self->Error(
            $cb,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_NOT_FOUND,
                message => 'id_not_found'
            )
        );
        return;
    }

    if ( exists $q->{last_results} and $q->{last_results} ) {
        my %test = %{ $TEST{ $q->{id} } };
        my $results = delete $test{results};
        $test{results} = scalar @$results < $q->{last_results} ? [ @$results ] : [ @{$results}[-$q->{last_results}..-1] ];
        $self->Successful( $cb, \%test );
        return;
    }

    if ( exists $q->{results} and !$q->{results} ) {
        my %test = %{ $TEST{ $q->{id} } };
        delete $test{results};
        $self->Successful( $cb, \%test );
        return;
    }

    $self->Successful( $cb, $TEST{ $q->{id} } );
    return;
}

=item ReadAnalyzeStatus

=cut

sub ReadAnalyzeStatus {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    unless ( exists $TEST{ $q->{id} } ) {
        $self->Error(
            $cb,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_NOT_FOUND,
                message => 'id_not_found'
            )
        );
        return;
    }

    $self->Successful( $cb, {
        status => $TEST{ $q->{id} }->{status},
        progress => $TEST{ $q->{id} }->{progress},
        update => $TEST{ $q->{id} }->{update}
    } );
    return;
}

=item DeleteAnalyze

=cut

sub DeleteAnalyze {
    my ( $self, $cb, $q ) = @_;
    $STAT{api}->{requests}++;

    unless ( exists $TEST{ $q->{id} } ) {
        $self->Error(
            $cb,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_NOT_FOUND,
                message => 'id_not_found'
            )
        );
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

1;    # End of Lim::Plugin::Zonalizer::Server