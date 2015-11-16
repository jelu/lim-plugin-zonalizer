package Lim::Plugin::Zonalizer::Server;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);

use Lim::Plugin::Zonalizer qw(:err :status);

use Lim              ();
use Lim::Error       ();
use OSSP::uuid       ();
use MIME::Base64     ();
use AnyEvent         ();
use AnyEvent::Handle ();
use JSON::XS         ();
use HTTP::Status     ();
use URI::Escape::XS  qw(uri_escape);

use Zonemaster::Translator ();
use Zonemaster::Logger::Entry ();
use POSIX qw(setlocale LC_MESSAGES);

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

our $TRANSLATOR;

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

    #
    # Default configuration
    #

    $self->{default_limit}     = 10;
    $self->{max_limit}         = 10;
    $self->{base_url}          = 1;
    $self->{db_driver}         = 'Memory';
    $self->{db_conf}           = {};
    $self->{lang}              = $ENV{LC_MESSAGES} || $ENV{LC_ALL} || $ENV{LANG} || $ENV{LANGUAGE} || 'en_US';
    $self->{lang}              =~ s/\..*$//o;

    #
    # Load configuration
    #

    if ( ref( Lim->Config->{zonalizer} ) eq 'HASH' ) {
        foreach ( qw(default_limit max_limit base_url db_driver custom_base_url lang) ) {
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

    if ( exists $self->{custom_base_url} ) {
        $self->{custom_base_url} =~ s/[\/\s]+$//o;
    }

    #
    # Load database
    #

    my $db_driver = 'Lim::Plugin::Zonalizer::DB::' . $self->{db_driver};
    eval 'use ' . $db_driver . ';';
    if ( $@ ) {
        confess $@;
    }
    $self->{db} = $db_driver->new( %{ $self->{db_conf} } );

    #
    # Build translator
    #

    unless ( $self->{lang} =~ /^[a-z]{2}_[A-Z]{2}$/o ) {
        confess 'Invalid language set for translations';
    }

    $TRANSLATOR = Zonemaster::Translator->new;
    $TRANSLATOR->data;

    unless ( setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' ) ) {
        confess 'Unsupported locale, setlocale( ' . $self->{lang} . '.UTF-8 ) failed: ' . $!;
    }

    #
    # Temporary memory scrubber
    #

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
    my $real_self = $self;
    weaken( $self );
    $STAT{api}->{requests}++;

    #
    # Verify limit and set base url if configured/requested.
    #

    my $limit = $q->{limit} > 0 ? $q->{limit} : $self->{default_limit};
    if ( $limit > $self->{max_limit} ) {
        $limit = $self->{max_limit};
    }
    my $base_url = '';
    if ( exists $self->{custom_base_url} ) {
        $base_url = $self->{custom_base_url};
    }
    elsif ( ( defined $q->{base_url} ? $q->{base_url} : $self->{base_url} ) and $cb->request ) {
        $base_url = $cb->request->header( 'X-Lim-Base-URL' );
    }

    #
    # Get translator
    #

    my ( $translator, $lang, $error ) = $self->GetTranslator( $q->{lang} );

    unless ( $translator and $lang ) {
        $self->Error(
            $cb,
            $error ? $error : Lim::Error->new(
                module => $self,
                code   => HTTP::Status::HTTP_INTERNAL_SERVER_ERROR
            )
        );
        return;
    }

    #
    # Returned in memory ongoing analysis if requested.
    #

    if ( defined $q->{ongoing} && $q->{ongoing} == 1 ) {
        my @analysis;

        foreach ( sort { $b->{update} <=> $a->{update} } values %TEST ) {
            my %test = %{$_};

            unless ( $q->{results} ) {
                delete $test{results};
            }
            else {
                my @results;

                setlocale( LC_MESSAGES, $lang . '.UTF-8' );
                foreach my $result ( @{ $test{results} } ) {
                    my $entry = Zonemaster::Logger::Entry->new( $result );
                    push( @results, {
                        %$result,
                        message => $translator->translate_tag( $entry )
                    });
                }
                setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' );

                $test{results} = \@results;
            }
            $test{url} = $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis/' . uri_escape( $test{id} );

            push( @analysis, \%test );

            if ( scalar @analysis == $limit ) {
                last;
            }
        }

        $self->Successful( $cb, { analysis => \@analysis } );
        return;
    }

    #
    # Query database for analysis.
    #

    $self->{db}->ReadAnalysis(
        %$q,
        limit => $limit,
        cb    => sub {
            my $paging = shift;
            my @analysis;

            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            if ( $@ ) {
                $STAT{api}->{errors}++;

                if ( $@ eq ERR_INVALID_LIMIT or $@ eq ERR_INVALID_SORT_FIELD ) {
                    $self->Error(
                        $cb,
                        Lim::Error->new(
                            module  => $self,
                            code    => HTTP::Status::HTTP_BAD_REQUEST,
                            message => $@
                        )
                    );
                    return;
                }

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( $@ );
                $self->Error(
                    $cb,
                    Lim::Error->new(
                        module => $self,
                        code   => HTTP::Status::HTTP_INTERNAL_SERVER_ERROR
                    )
                );
                return;
            }

            #
            # Construct the result
            #

            if ( defined $q->{results} and $q->{results} == 1 ) {
                setlocale( LC_MESSAGES, $lang . '.UTF-8' );
                foreach ( @_ ) {
                    unless ( ref( $_->{results} ) eq 'ARRAY' ) {
                        next;
                    }

                    foreach my $result ( @{ $_->{results} } ) {
                        my $entry = Zonemaster::Logger::Entry->new( $result );
                        $result->{message} = $translator->translate_tag( $entry );
                    }
                }
                setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' );
            }
            foreach ( @_ ) {
                push(
                    @analysis,
                    {
                        id       => $_->{id},
                        fqdn     => $_->{fqdn},
                        url      => $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis/' . uri_escape( $_->{id} ),
                        status   => $_->{status},
                        progress => $_->{progress},
                        created  => $_->{created},
                        updated  => $_->{updated},
                        exists $_->{error} ? ( error => $_->{error} ) : (),
                        defined $q->{results} && $q->{results} == 1 && exists $_->{results} ? ( results => $_->{results} ) : (),
                        summary => {
                            notice => $_->{summary}->{notice},
                            warning => $_->{summary}->{warning},
                            error => $_->{summary}->{error},
                            critical => $_->{summary}->{critical}
                        }
                    }
                );
            }

            $self->Successful(
                $cb,
                {
                    analysis => \@analysis,
                    defined $paging
                    ? (
                        paging => {
                            cursors => {
                                after  => $paging->{after},
                                before => $paging->{before}
                            },
                            $paging->{previous} ? ( previous => $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis?limit=' . uri_escape( $limit ) . '&before=' . uri_escape( $paging->{before} ) . ( defined $q->{sort} ? '&sort=' . uri_escape( $q->{sort} ) : '' ) . ( defined $q->{direction} ? '&direction=' . uri_escape( $q->{direction} ) : '' ) . ( defined $paging->{extra} ? '&' . $paging->{extra} : '' ) ) : (),
                            $paging->{next}     ? ( next     => $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis?limit=' . uri_escape( $limit ) . '&after=' . uri_escape( $paging->{after} ) .   ( defined $q->{sort} ? '&sort=' . uri_escape( $q->{sort} ) : '' ) . ( defined $q->{direction} ? '&direction=' . uri_escape( $q->{direction} ) : '' ) . ( defined $paging->{extra} ? '&' . $paging->{extra} : '' ) ) : ()
                        }
                      )
                    : ()
                }
            );
        }
    );
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
    my $real_self = $self;
    weaken( $self );
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

    $self->{logger}->debug('Analyzing ', $q->{fqdn}, ' ', $id);

    my $test = $TEST{$id} = {
        id       => $id,
        fqdn     => $q->{fqdn},
        status   => 'analyzing',
        progress => 0,
        created  => time,
        updated  => time,
        summary  => {
            notice => 0,
            warning => 0,
            error => 0,
            critical => 0
        }
    };

    my $cli;
    unless ( open( $cli, '-|:encoding(UTF-8)', 'zonemaster-cli', qw(--json_stream --no-ipv6 --level DEBUG), $q->{fqdn} ) ) {
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
    my $store = sub {
        $self->StoreAnalyze( $id );
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
                if ( defined $store ) {
                    $store->();
                    undef $store;
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

                    if ( $msg->{level} eq 'NOTICE' ) {
                        $test->{summary}->{notice}++;
                    }
                    elsif ( $msg->{level} eq 'WARNING' ) {
                        $test->{summary}->{warning}++;
                    }
                    elsif ( $msg->{level} eq 'ERROR' ) {
                        $test->{summary}->{error}++;
                    }
                    elsif ( $msg->{level} eq 'CRITICAL' ) {
                        $test->{summary}->{critical}++;
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
                if ( defined $store ) {
                    $store->();
                    undef $store;
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
            if ( defined $store ) {
                $store->();
                undef $store;
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
            if ( defined $store ) {
                $store->();
                undef $store;
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
    my $real_self = $self;
    weaken( $self );
    $STAT{api}->{requests}++;

    #
    # Set base url if configured/requested.
    #

    my $base_url = '';
    if ( exists $self->{custom_base_url} ) {
        $base_url = $self->{custom_base_url};
    }
    elsif ( ( defined $q->{base_url} ? $q->{base_url} : $self->{base_url} ) and $cb->request ) {
        $base_url = $cb->request->header( 'X-Lim-Base-URL' );
    }

    #
    # Get translator
    #

    my ( $translator, $lang, $error ) = $self->GetTranslator( $q->{lang} );

    unless ( $translator and $lang ) {
        $self->Error(
            $cb,
            $error ? $error : Lim::Error->new(
                module => $self,
                code   => HTTP::Status::HTTP_INTERNAL_SERVER_ERROR
            )
        );
        return;
    }

    #
    # Check for analyze in memory.
    #

    if ( exists $TEST{ $q->{id} } ) {
        my %test = %{ $TEST{ $q->{id} } };
        $test{url} = $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis/' . uri_escape( $test{id} );

        if ( exists $q->{last_results} and $q->{last_results} ) {
            my $results = delete $test{results};
            $test{results} = scalar @$results < $q->{last_results} ? [ @$results ] : [ @{$results}[-$q->{last_results}..-1] ];
        }
        elsif ( exists $q->{results} and !$q->{results} ) {
            delete $test{results};
        }

        if ( exists $test{results} ) {
            my @results;

            setlocale( LC_MESSAGES, $lang . '.UTF-8' );
            foreach my $result ( @{ $test{results} } ) {
                my $entry = Zonemaster::Logger::Entry->new( $result );
                push( @results, {
                    %$result,
                    message => $translator->translate_tag( $entry )
                });
            }
            setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' );

            $test{results} = \@results;
        }

        $self->Successful( $cb, \%test );
        return;
    }

    #
    # Query the database for the analyze.
    #

    $self->{db}->ReadAnalyze(
        id => $q->{id},
        cb => sub {
            my ( $analyze ) = @_;

            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            if ( $@ ) {
                $STAT{api}->{errors}++;

                if ( $@ eq ERR_ID_NOT_FOUND ) {
                    $self->Error(
                        $cb,
                        Lim::Error->new(
                            module  => $self,
                            code    => HTTP::Status::HTTP_NOT_FOUND,
                            message => $@
                        )
                    );
                    return;
                }

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( $@ );
                $self->Error(
                    $cb,
                    Lim::Error->new(
                        module => $self,
                        code   => HTTP::Status::HTTP_INTERNAL_SERVER_ERROR
                    )
                );
                return;
            }

            #
            # Construct the result
            #

            if ( exists $q->{last_results} and $q->{last_results} ) {
                my %test = %{ $TEST{ $q->{id} } };
                my $results = delete $analyze->{results};
                $analyze->{results} = scalar @$results < $q->{last_results} ? [ @$results ] : [ @{$results}[-$q->{last_results}..-1] ];
            }
            elsif ( exists $q->{results} and !$q->{results} ) {
                delete $analyze->{results};
            }

            if ( exists $analyze->{results} ) {
                setlocale( LC_MESSAGES, $lang . '.UTF-8' );
                foreach my $result ( @{ $analyze->{results} } ) {
                    my $entry = Zonemaster::Logger::Entry->new( $result );
                    $result->{message} = $translator->translate_tag( $entry );
                }
                setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' );
            }

            $self->Successful(
                $cb,
                {
                    id       => $analyze->{id},
                    fqdn     => $analyze->{fqdn},
                    url      => $base_url . '/zonalizer/' . uri_escape( $q->{version} ) . '/analysis/' . uri_escape( $analyze->{id} ),
                    status   => $analyze->{status},
                    progress => $analyze->{progress},
                    created  => $analyze->{created},
                    updated  => $analyze->{updated},
                    exists $analyze->{error} ? ( error => $analyze->{error} ) : (),
                    exists $analyze->{results} ? ( results => $analyze->{results} ) : (),
                    summary => {
                        notice => $analyze->{summary}->{notice},
                        warning => $analyze->{summary}->{warning},
                        error => $analyze->{summary}->{error},
                        critical => $analyze->{summary}->{critical}
                    }
                }
            );
        }
    );
    return;
}

=item ReadAnalyzeStatus

=cut

sub ReadAnalyzeStatus {
    my ( $self, $cb, $q ) = @_;
    my $real_self = $self;
    weaken( $self );
    $STAT{api}->{requests}++;

    #
    # Check for analyze in memory.
    #

    if ( exists $TEST{ $q->{id} } ) {
        $self->Successful( $cb, {
            status => $TEST{ $q->{id} }->{status},
            progress => $TEST{ $q->{id} }->{progress},
            update => $TEST{ $q->{id} }->{update}
        } );
        return;
    }

    #
    # Query the database for the analyze.
    #

    $self->{db}->ReadAnalyze(
        id => $q->{id},
        cb => sub {
            my ( $analyze ) = @_;

            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            if ( $@ ) {
                $STAT{api}->{errors}++;

                if ( $@ eq ERR_ID_NOT_FOUND ) {
                    $self->Error(
                        $cb,
                        Lim::Error->new(
                            module  => $self,
                            code    => HTTP::Status::HTTP_NOT_FOUND,
                            message => $@
                        )
                    );
                    return;
                }

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( $@ );
                $self->Error(
                    $cb,
                    Lim::Error->new(
                        module => $self,
                        code   => HTTP::Status::HTTP_INTERNAL_SERVER_ERROR
                    )
                );
                return;
            }

            #
            # Construct the result
            #

            $self->Successful(
                $cb,
                {
                    status   => $analyze->{status},
                    progress => $analyze->{progress},
                    updated  => $analyze->{updated}
                }
            );
        }
    );
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

=head1 PRIVATE METHODS

=item StoreAnalyze

=cut

sub StoreAnalyze {
    my ( $self, $id ) = @_;

    unless ( defined $id and exists $TEST{ $id } ) {
        return;
    }

    $self->{logger}->debug('Storing ', $id);

    $self->{db}->CreateAnalyze(
        analyze => $TEST{ $id },
        cb => sub {
            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            if ( $@ ) {
                $self->{logger}->error( 'Unable to store ', $id, ' in database, analyze will be lost: ', $@ );
            }

            delete $TEST{ $id };
        }
    );
    return;
}

=item GetTranslator

=cut

sub GetTranslator {
    my ( $self, $lang ) = @_;

    unless ( $lang ) {
        $lang = $self->{lang};
    }

    unless ( $lang =~ /^[a-z]{2}_[A-Z]{2}$/o and setlocale( LC_MESSAGES, $lang . '.UTF-8' ) ) {

        # uncoverable branch false
        Lim::ERR and $self->{logger}->error( 'Invalid language ', $lang );

        return (
            undef,
            undef,
            Lim::Error->new(
                module  => $self,
                code    => HTTP::Status::HTTP_UNSUPPORTED_MEDIA_TYPE,
                message => 'invalid_lang'
            )
        );
    }

    setlocale( LC_MESSAGES, $self->{lang} . '.UTF-8' );

    return ( $TRANSLATOR, $lang );
}

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
