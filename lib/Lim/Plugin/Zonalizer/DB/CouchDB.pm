package Lim::Plugin::Zonalizer::DB::CouchDB;

use utf8;
use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);

use Lim               ();
use AnyEvent::CouchDB ();
use AnyEvent::HTTP    ();
use Lim::Plugin::Zonalizer qw(:err);
use URI::Escape::XS qw(uri_escape);
use JSON ();
use Clone qw(clone);

use base qw(Lim::Plugin::Zonalizer::DB);

our %VALID_ORDER_FIELD = (
    analysis => { map { $_ => 1 } ( qw(created updated) ) }
);
our $ID_DELIMITER = ':';

=encoding utf8

=head1 NAME

Lim::Plugin::Zonalizer::DB::CouchDB - The CouchDB database for Zonalizer

=head1 METHODS

=over 4

=item Init

=cut

sub Init {
    my ( $self, %args ) = @_;

    $self->{delete_batch} = 100;

    foreach ( qw(uri) ) {
        unless ( defined $args{$_} ) {
            confess 'configuration: ' . $_ . ' is not defined';
        }
    }

    foreach ( qw(delete_batch) ) {
        if ( defined $args{$_} ) {
            $self->{$_} = $args{$_};
        }
    }

    $self->{db} = AnyEvent::CouchDB::couchdb( $args{uri} );
    return;
}

=item Destroy

=cut

sub Destroy {
}

=item Name

=cut

sub Name {
    return 'CouchDB';
}

=item $db->ReadAnalysis

=cut

sub ReadAnalysis {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    undef $@;

    my $limit = defined $args{limit} ? $args{limit} : 0;
    if ( $limit == 0 ) {
        $args{cb}->();
        return;
    }
    unless ( $limit > 0 ) {
        $@ = ERR_INVALID_LIMIT;
        $args{cb}->();
        return;
    }

    my $search_fqdn;
    my $search_fqdn2;
    if ( defined $args{search} ) {
        if ( $args{search} =~ /^\./o ) {
            $search_fqdn2 = $args{search};
            $search_fqdn2 =~ s/^\.//o;
            $search_fqdn2 =~ s/\.$//o;
        }
        else {
            $search_fqdn = $args{search};
            unless ( $search_fqdn =~ /\.$/o ) {
                $search_fqdn .= '.';
            }
        }
    }

    my $view   = 'all';
    my %option = (
        include_docs => 1,
        limit        => $limit
    );
    my $ignore_paging = 0;
    my $reverse       = 0;

    if ( defined $search_fqdn ) {
        $option{key} = [ $search_fqdn, undef ];
        $view = 'by_fqdn';
        $ignore_paging = 1;
    }
    elsif ( defined $search_fqdn2 ) {
        if ( defined $args{after} ) {
            $option{startkey} = [ split( /$ID_DELIMITER/o, $args{after} ), {} ];
            $option{endkey} = [ '', reverse( split( /\./o, $search_fqdn2 ) ), {} ];
        }
        elsif ( defined $args{before} ) {
            $reverse = 1;
            $option{startkey} = [ split( /$ID_DELIMITER/o, $args{before} ) ];
            $option{endkey} = [ '', reverse( split( /\./o, $search_fqdn2 ) ) ];
        }
        else {
            $option{startkey} = [ '', reverse( split( /\./o, $search_fqdn2 ) ) ];
            $option{endkey} = [ '', reverse( split( /\./o, $search_fqdn2 ) ), {} ];
        }

        $view = 'by_rfqdn';
    }
    elsif ( defined $args{sort} ) {
        if ( $args{direction} eq 'descending' ) {
            $option{descending} = 1;
        }

        unless ( exists $VALID_ORDER_FIELD{analysis}->{ $args{sort} } ) {
            $@ = ERR_INVALID_SORT_FIELD;
            $args{cb}->();
            return;
        }

        if ( defined $args{after} ) {
            $option{startkey} = [ split( /$ID_DELIMITER/o, $args{after} ), !$option{descending} ? ( {} ) : () ];
            unless ( scalar @{ $option{startkey} } == 2 + ( !$option{descending} ? 1 : 0 ) ) {
                $@ = ERR_INVALID_AFTER;
                $args{cb}->();
                return;
            }

            # uncoverable branch false
            if ( $VALID_ORDER_FIELD{analysis}->{ $args{sort} } == 1 ) {
                $option{startkey}->[0] = $option{startkey}->[0] + 0;
            }
        }
        elsif ( defined $args{before} ) {
            $reverse = 1;
            $option{startkey} = [ split( /$ID_DELIMITER/o, $args{before} ), $option{descending} ? ( {} ) : () ];
            unless ( scalar @{ $option{startkey} } == 2 + ( $option{descending} ? 1 : 0 ) ) {
                $@ = ERR_INVALID_BEFORE;
                $args{cb}->();
                return;
            }

            # uncoverable branch false
            if ( $VALID_ORDER_FIELD{analysis}->{ $args{sort} } == 1 ) {
                $option{startkey}->[0] = $option{startkey}->[0] + 0;
            }
        }

        $view = 'by_' . $args{sort};
    }
    else {
        if ( defined $args{after} ) {
            $option{startkey} = [ $args{after}, {} ];
        }
        elsif ( defined $args{before} ) {
            $reverse = 1;
            $option{startkey} = [ $args{before} ];
        }
    }

    if ( $reverse ) {
        if ( $option{descending} ) {
            delete $option{descending};
        }
        else {
            $option{descending} = 1;
        }
    }

    # uncoverable branch false
    Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/', $view );
    $self->{db}->view( 'analysis/' . $view, \%option )->cb(
        sub {
            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            my ( $before, $after, $previous, $next, $rows, $total_rows, $offset );
            eval { ( $before, $after, $previous, $next, $rows, $total_rows, $offset ) = $self->HandleResponse( $_[0], $reverse ); };
            if ( $@ ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->();
                return;
            }

            unless ( $offset ) {
                $previous = 0;
            }

            my $code = sub {
                $args{cb}->(
                    ( $previous || $next ) && !$ignore_paging
                    ? {
                        before   => $before,
                        after    => $after,
                        previous => $previous,
                        next     => $next,
                        defined $search_fqdn || defined $search_fqdn2 ? ( extra => 'search=' . uri_escape( defined $search_fqdn ? $search_fqdn : $search_fqdn2 ) ) : ()
                      }
                    : undef,
                    @$rows
                );
            };

            unless ( scalar @$rows ) {
                $ignore_paging = 1;
                $code->();
                return;
            }

            unless ( defined $search_fqdn2 ) {
                $code->();
                return;
            }

            #
            # We need to swap after/before since we are using a descending
            # view when doing subdomain searches but HandleResponse does not
            # know about this.
            #
            if ( $reverse ) {
                my $a = $after;
                my $b = $before;
                $before = $a;
                $after  = $b;
            }

            # TODO: Can this be solved in a better way then fetching previous/next with skip?

            $option{limit} = 1;
            delete $option{startkey};
            delete $option{endkey};
            delete $option{include_docs};
            my $rfqdn = join( '.', '', reverse( split( /\./o, $search_fqdn2 ) ) ) . '.';

            my $code_next = sub {
                unless ( $next ) {
                    $code->();
                    return;
                }

                if ( $reverse ) {

                    # uncoverable branch false
                    Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/', $view, ' next check (reverse), skip ', $offset - 1 );
                    $option{skip} = $offset - 1;
                }
                else {
                    # uncoverable branch false
                    Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/', $view, ' next check, skip ', $offset + scalar @$rows );
                    $option{skip} = $offset + scalar @$rows;
                }
                $self->{db}->view( 'analysis/' . $view, \%option )->cb(
                    sub {
                        # uncoverable branch true
                        unless ( defined $self ) {

                            # uncoverable statement
                            return;
                        }

                        my ( $keys );
                        eval { $keys = $self->HandleResponseKey( $_[0] ); };
                        if ( $@ ) {

                            # uncoverable branch false
                            Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            $@ = ERR_INTERNAL_DATABASE;
                            $args{cb}->();
                            return;
                        }

                        unless ( scalar @$keys and substr( join( '.', @{ $keys->[0] } ) . '.', 0, length( $rfqdn ) ) eq $rfqdn ) {
                            $next = 0;
                        }

                        $code->();
                    }
                );
            };

            unless ( $previous ) {
                $code_next->();
                return;
            }

            if ( $reverse ) {

                # uncoverable branch false
                Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/', $view, ' previous check (reverse), skip ', $offset + scalar @$rows );
                $option{skip} = $offset + scalar @$rows;
            }
            else {
                # uncoverable branch false
                Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/', $view, ' previous check, skip ', $offset - 1 );
                $option{skip} = $offset - 1;
            }
            $self->{db}->view( 'analysis/' . $view, \%option )->cb(
                sub {
                    # uncoverable branch true
                    unless ( defined $self ) {

                        # uncoverable statement
                        return;
                    }

                    my ( $keys );
                    eval { $keys = $self->HandleResponseKey( $_[0] ); };
                    if ( $@ ) {

                        # uncoverable branch false
                        Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                        $@ = ERR_INTERNAL_DATABASE;
                        $args{cb}->();
                        return;
                    }

                    unless ( scalar @$keys and substr( join( '.', @{ $keys->[0] } ) . '.', 0, length( $rfqdn ) ) eq $rfqdn ) {
                        $previous = 0;
                    }

                    $code_next->();
                }
            );
        }
    );
    return;
}

=item DeleteAnalysis

=over 4

=item cb => sub { my ($deleted_analysis, $deleted_checks, $deleted_results) = @_; ... }

$@ on error

=back

=cut

sub DeleteAnalysis {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    undef $@;

    my ( $deleted_analysis, $deleted_checks, $deleted_results ) = ( 0, 0, 0 );
    my $analysis;
    $analysis = sub {

        # uncoverable branch false
        Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/all' );
        $self->{db}->view( 'analysis/all', { limit => $self->{delete_batch}, include_docs => 1 } )->cb(
            sub {
                # uncoverable branch true
                unless ( defined $self ) {

                    # uncoverable statement
                    return;
                }

                my $rows;
                eval { $rows = $self->HandleResponseIdRev( $_[0] ); };
                if ( $@ ) {

                    # uncoverable branch false
                    Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                    $@ = ERR_INTERNAL_DATABASE;
                    $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                    return;
                }

                unless ( scalar @$rows ) {
                    $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                    return;
                }

                foreach ( @$rows ) {
                    $_->{_deleted} = JSON::true;
                }

                # uncoverable branch false
                Lim::DEBUG and $self->{logger}->debug( 'couchdb bulk_docs analysis' );
                $self->{db}->bulk_docs( $rows )->cb(
                    sub {
                        my ( $cv ) = @_;

                        # uncoverable branch true
                        unless ( defined $self ) {

                            # uncoverable statement
                            return;
                        }

                        eval { $cv->recv; };
                        if ( $@ ) {

                            # uncoverable branch false
                            Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            $@ = ERR_INTERNAL_DATABASE;
                            $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                            return;
                        }

                        $deleted_analysis += scalar @$rows;
                        $analysis->();
                    }
                );
            }
        );
    };
    my $checks;
    $checks = sub {

        # uncoverable branch false
        Lim::DEBUG and $self->{logger}->debug( 'couchdb checks/all' );
        $self->{db}->view( 'checks/all', { limit => $self->{delete_batch}, include_docs => 1 } )->cb(
            sub {
                # uncoverable branch true
                unless ( defined $self ) {

                    # uncoverable statement
                    return;
                }

                my $rows;
                eval { $rows = $self->HandleResponseIdRev( $_[0] ); };
                if ( $@ ) {

                    # uncoverable branch false
                    Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                    $@ = ERR_INTERNAL_DATABASE;
                    $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                    return;
                }

                unless ( scalar @$rows ) {
                    $analysis->();
                    return;
                }

                foreach ( @$rows ) {
                    $_->{_deleted} = JSON::true;
                }

                # uncoverable branch false
                Lim::DEBUG and $self->{logger}->debug( 'couchdb bulk_docs checks' );
                $self->{db}->bulk_docs( $rows )->cb(
                    sub {
                        my ( $cv ) = @_;

                        # uncoverable branch true
                        unless ( defined $self ) {

                            # uncoverable statement
                            return;
                        }

                        eval { $cv->recv; };
                        if ( $@ ) {

                            # uncoverable branch false
                            Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            $@ = ERR_INTERNAL_DATABASE;
                            $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                            return;
                        }

                        $deleted_checks += scalar @$rows;
                        $checks->();
                    }
                );
            }
        );
    };
    my $results;
    $results = sub {

        # uncoverable branch false
        Lim::DEBUG and $self->{logger}->debug( 'couchdb results/all' );
        $self->{db}->view( 'results/all', { limit => $self->{delete_batch}, include_docs => 1 } )->cb(
            sub {
                # uncoverable branch true
                unless ( defined $self ) {

                    # uncoverable statement
                    return;
                }

                my $rows;
                eval { $rows = $self->HandleResponseIdRev( $_[0] ); };
                if ( $@ ) {

                    # uncoverable branch false
                    Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                    $@ = ERR_INTERNAL_DATABASE;
                    $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                    return;
                }

                unless ( scalar @$rows ) {
                    $checks->();
                    return;
                }

                foreach ( @$rows ) {
                    $_->{_deleted} = JSON::true;
                }

                # uncoverable branch false
                Lim::DEBUG and $self->{logger}->debug( 'couchdb bulk_docs results' );
                $self->{db}->bulk_docs( $rows )->cb(
                    sub {
                        my ( $cv ) = @_;

                        # uncoverable branch true
                        unless ( defined $self ) {

                            # uncoverable statement
                            return;
                        }

                        eval { $cv->recv; };
                        if ( $@ ) {

                            # uncoverable branch false
                            Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            $@ = ERR_INTERNAL_DATABASE;
                            $args{cb}->( $deleted_analysis, $deleted_checks, $deleted_results );
                            return;
                        }

                        $deleted_results += scalar @$rows;
                        $results->();
                    }
                );
            }
        );
    };
    $results->();
    return;
}

=item CreateAnalyze

=cut

sub CreateAnalyze {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    $self->ValidateAnalyze( $args{analyze} );
    undef $@;

    if ( exists $args{analyze}->{_id} or exists $args{analyze}->{_rev} ) {

        # uncoverable branch false
        Lim::ERR and $self->{logger}->error( 'CouchDB specific fields _id/_rev existed during create' );
        $@ = ERR_INTERNAL_DATABASE;
        $args{cb}->();
        return;
    }

    my %analyze = ( %{ clone $args{analyze} }, type => 'new_analyze' );

    # uncoverable branch false
    Lim::DEBUG and $self->{logger}->debug( 'couchdb save_doc new_analyze' );
    $self->{db}->save_doc( \%analyze )->cb(
        sub {
            my ( $cv ) = @_;

            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            eval { $cv->recv; };
            if ( $@ ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->();
                return;
            }

            # uncoverable branch false
            Lim::DEBUG and $self->{logger}->debug( 'couchdb new_analysis/all ', $analyze{id} );
            $self->{db}->view( 'new_analysis/all', { key => $analyze{id} } )->cb(
                sub {
                    # uncoverable branch true
                    unless ( defined $self ) {

                        # uncoverable statement
                        return;
                    }

                    my $rows;
                    eval { $rows = $self->HandleResponseId( $_[0] ); };
                    if ( $@ ) {

                        # uncoverable branch false
                        Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                        $@ = ERR_INTERNAL_DATABASE;
                        $args{cb}->();
                        return;
                    }
                    unless ( scalar @$rows ) {
                        $self->{db}->remove_doc( \%analyze )->cb(
                            sub {
                                eval { $_[0]->recv; };

                                # uncoverable branch true
                                unless ( defined $self ) {

                                    # uncoverable statement
                                    return;
                                }

                                # uncoverable branch false
                                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            }
                        );

                        # uncoverable branch false
                        Lim::ERR and $self->{logger}->error( 'CouchDB error: created analyze but was not returned' );
                        $@ = ERR_INTERNAL_DATABASE;
                        $args{cb}->();
                        return;
                    }
                    unless ( scalar @$rows == 1 ) {
                        $self->{db}->remove_doc( \%analyze )->cb(
                            sub {
                                eval { $_[0]->recv; };

                                # uncoverable branch true
                                unless ( defined $self ) {

                                    # uncoverable statement
                                    return;
                                }

                                # uncoverable branch false
                                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                            }
                        );
                        $@ = ERR_DUPLICATE_ID;
                        $args{cb}->();
                        return;
                    }


                    $analyze{type} = 'analyze';

                    # uncoverable branch false
                    Lim::DEBUG and $self->{logger}->debug( 'couchdb save_doc analyze' );
                    $self->{db}->save_doc( \%analyze )->cb(
                        sub {
                            my ( $cv ) = @_;

                            # uncoverable branch true
                            unless ( defined $self ) {

                                # uncoverable statement
                                return;
                            }

                            eval { $cv->recv; };
                            if ( $@ ) {
                                $self->{db}->remove_doc( \%analyze )->cb(
                                    sub {
                                        eval { $_[0]->recv; };

                                        # uncoverable branch true
                                        unless ( defined $self ) {

                                            # uncoverable statement
                                            return;
                                        }

                                        # uncoverable branch false
                                        Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                                    }
                                );

                                # uncoverable branch false
                                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                                $@ = ERR_INTERNAL_DATABASE;
                                $args{cb}->();
                                return;
                            }

                            $args{cb}->( \%analyze );
                        }
                    );
                }
            );
        }
    );
    return;
}

=item ReadAnalyze

=cut

sub ReadAnalyze {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    unless ( defined $args{id} ) {
        confess 'id is not defined';
    }
    undef $@;

    # uncoverable branch false
    Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/all ', $args{id} );
    $self->{db}->view( 'analysis/all', { key => [ $args{id}, undef ], include_docs => 1 } )->cb(
        sub {
            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            my $rows;
            eval { $rows = $self->HandleResponse( $_[0] ); };
            if ( $@ ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->();
                return;
            }
            unless ( scalar @$rows ) {
                $@ = ERR_ID_NOT_FOUND;
                $args{cb}->();
                return;
            }
            if ( scalar @$rows > 1 ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: too many rows returned' );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->();
                return;
            }

            $args{cb}->( $rows->[0] );
        }
    );
    return;
}

=item UpdateAnalyze

=cut

sub UpdateAnalyze {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    $self->ValidateAnalyze( $args{analyze} );
    undef $@;

    unless ( defined $args{analyze}->{_id} ) {

        # uncoverable branch false
        Lim::ERR and $self->{logger}->error( 'CouchDB specific _id is missing' );
        $@ = ERR_ID_NOT_FOUND;
        $args{cb}->();
        return;
    }
    unless ( defined $args{analyze}->{_rev} ) {

        # uncoverable branch false
        Lim::ERR and $self->{logger}->error( 'CouchDB specific _rev is missing' );
        $@ = ERR_REVISION_MISSMATCH;
        $args{cb}->();
        return;
    }

    # uncoverable branch false
    Lim::DEBUG and $self->{logger}->debug( 'couchdb save_doc analyze' );
    my $analyze = clone $args{analyze};
    $self->{db}->save_doc( $analyze )->cb(
        sub {
            my ( $cv ) = @_;

            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            eval { $cv->recv; };
            if ( $@ ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->();
                return;
            }

            $args{cb}->( $analyze );
        }
    );
    return;
}

=item DeleteAnalyze

=cut

sub DeleteAnalyze {
    my ( $self, %args ) = @_;
    my $real_self = $self;
    weaken( $self );

    unless ( ref( $args{cb} ) eq 'CODE' ) {
        confess 'cb is not CODE';
    }
    unless ( defined $args{id} ) {
        confess 'id is not defined';
    }
    undef $@;

    # uncoverable branch false
    Lim::DEBUG and $self->{logger}->debug( 'couchdb analysis/all ', $args{id} );
    $self->{db}->view( 'analysis/all', { key => [ $args{id}, undef ], include_docs => 1 } )->cb(
        sub {
            # uncoverable branch true
            unless ( defined $self ) {

                # uncoverable statement
                return;
            }

            my $rows;
            eval { $rows = $self->HandleResponse( $_[0] ); };
            if ( $@ ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->( 0, 0 );
                return;
            }
            unless ( scalar @$rows ) {
                $@ = ERR_ID_NOT_FOUND;
                $args{cb}->( 0, 0 );
                return;
            }
            if ( scalar @$rows > 1 ) {

                # uncoverable branch false
                Lim::ERR and $self->{logger}->error( 'CouchDB error: too many rows returned' );
                $@ = ERR_INTERNAL_DATABASE;
                $args{cb}->( 0, 0 );
                return;
            }

            $self->DeleteAnalyzeChecks(
                id => $args{id},
                cb => sub {
                    my ( $deleted_checks, $deleted_results ) = @_;

                    if ( $@ ) {
                        $args{cb}->( 0, 0 );
                        return;
                    }

                    $rows->[0]->{_deleted} = JSON::true;

                    # uncoverable branch false
                    Lim::DEBUG and $self->{logger}->debug( 'couchdb save_doc ', $args{id} );
                    $self->{db}->save_doc( $rows->[0] )->cb(
                        sub {
                            my ( $cv ) = @_;

                            # uncoverable branch true
                            unless ( defined $self ) {

                                # uncoverable statement
                                return;
                            }

                            eval { $cv->recv; };
                            if ( blessed $@ and $@->can( 'headers' ) and ref( $@->headers ) eq 'HASH' and $@->headers->{Status} == 200 and $@->headers->{Reason} eq 'OK' ) {
                                undef $@;
                            }
                            if ( $@ ) {

                                # uncoverable branch false
                                Lim::ERR and $self->{logger}->error( 'CouchDB error: ', $@ );
                                $@ = ERR_INTERNAL_DATABASE;
                            }

                            $args{cb}->( $deleted_checks, $deleted_results );
                        }
                    );
                }
            );
        }
    );
    return;
}

=back

=head1 PRIVATE METHODS

=over 4

=item HandleResponse

=cut

sub HandleResponse {
    my ( $self, $cv, $reverse, $keyskip ) = @_;

    unless ( blessed $cv and $cv->can( 'recv' ) ) {
        die 'cv is not object';
    }

    my $data = $cv->recv;

    unless ( ref( $data ) eq 'HASH' ) {
        die 'data is not HASH';
    }
    foreach ( qw(offset total_rows rows) ) {
        unless ( defined $data->{$_} ) {
            die 'data->' . $_ . ' is not defined';
        }
    }
    unless ( ref( $data->{rows} ) eq 'ARRAY' ) {
        die 'data->rows is not ARRAY';
    }

    my ( $before, $after, $previous, $next, @rows ) = ( undef, undef, 0, 0 );

    foreach ( @{ $data->{rows} } ) {
        unless ( ref( $_ ) eq 'HASH' ) {
            die 'data->rows[] entry is not HASH';
        }
        unless ( ref( $_->{key} ) eq 'ARRAY' ) {
            die 'data->rows[]->key is not ARRAY';
        }
        unless ( ref( $_->{doc} ) eq 'HASH' ) {
            die 'data->rows[]->doc is not HASH';
        }
        push( @rows, $_->{doc} );
    }

    unless ( wantarray ) {
        return \@rows;
    }

    if ( $reverse ) {
        @rows = reverse @rows;

        if ( $data->{offset} > 0 ) {
            $next = 1;
        }
        if ( ( $data->{total_rows} - $data->{offset} - scalar @rows ) > 0 ) {
            $previous = 1;
        }
    }
    else {
        if ( $data->{offset} > 0 ) {
            $previous = 1;
        }
        if ( ( $data->{total_rows} - $data->{offset} - scalar @rows ) > 0 ) {
            $next = 1;
        }
    }

    if ( $keyskip ) {
        my ( $skip, @key );

        @key = grep { defined $_ } @{ $data->{rows}->[0]->{key} };
        $skip = $keyskip;
        while ( $skip-- ) {
            shift( @key );
        }
        $before = join( $ID_DELIMITER, @key );

        @key = grep { defined $_ } @{ $data->{rows}->[-1]->{key} };
        $skip = $keyskip;
        while ( $skip-- ) {
            shift( @key );
        }
        $after = join( $ID_DELIMITER, @key );
    }
    else {
        $before = join( $ID_DELIMITER, grep { defined $_ } @{ $data->{rows}->[0]->{key} } );
        $after  = join( $ID_DELIMITER, grep { defined $_ } @{ $data->{rows}->[-1]->{key} } );
    }

    return ( $before, $after, $previous, $next, \@rows, $data->{total_rows}, $data->{offset} );
}

=item HandleResponseKey

=cut

sub HandleResponseKey {
    my ( $self, $cv ) = @_;

    unless ( blessed $cv and $cv->can( 'recv' ) ) {
        die 'cv is not object';
    }

    my $data = $cv->recv;

    unless ( ref( $data ) eq 'HASH' ) {
        die 'data is not HASH';
    }
    foreach ( qw(rows) ) {
        unless ( defined $data->{$_} ) {
            die 'data->' . $_ . ' is not defined';
        }
    }
    unless ( ref( $data->{rows} ) eq 'ARRAY' ) {
        die 'data->rows is not ARRAY';
    }

    my @rows;

    foreach ( @{ $data->{rows} } ) {
        unless ( ref( $_ ) eq 'HASH' ) {
            die 'data->rows[] entry is not HASH';
        }
        if ( exists $_->{doc} ) {
            unless ( ref( $_->{doc} ) eq 'HASH' ) {
                die 'data->rows[]->doc is not HASH';
            }
            push( @rows, $_->{doc} );
        }
        elsif ( ref( $_->{key} ) eq 'ARRAY' ) {
            push( @rows, [ grep { defined $_ } @{ $_->{key} } ] );
        }
        else {
            push( @rows, $_->{key} );
        }
    }

    return \@rows;
}

=item HandleResponseId

=cut

sub HandleResponseId {
    my ( $self, $cv ) = @_;

    unless ( blessed $cv and $cv->can( 'recv' ) ) {
        die 'cv is not object';
    }

    my $data = $cv->recv;

    unless ( ref( $data ) eq 'HASH' ) {
        die 'data is not HASH';
    }
    foreach ( qw(rows) ) {
        unless ( defined $data->{$_} ) {
            die 'data->' . $_ . ' is not defined';
        }
    }
    unless ( ref( $data->{rows} ) eq 'ARRAY' ) {
        die 'data->rows is not ARRAY';
    }

    my @rows;

    foreach ( @{ $data->{rows} } ) {
        unless ( ref( $_ ) eq 'HASH' ) {
            die 'data->rows[] entry is not HASH';
        }
        unless ( defined $_->{id} ) {
            die 'data->rows[]->id is not defined';
        }
        push( @rows, $_->{id} );
    }

    return \@rows;
}

=item HandleResponseIdRev

=cut

sub HandleResponseIdRev {
    my ( $self, $cv ) = @_;

    unless ( blessed $cv and $cv->can( 'recv' ) ) {
        die 'cv is not object';
    }

    my $data = $cv->recv;

    unless ( ref( $data ) eq 'HASH' ) {
        die 'data is not HASH';
    }
    foreach ( qw(rows) ) {
        unless ( defined $data->{$_} ) {
            die 'data->' . $_ . ' is not defined';
        }
    }
    unless ( ref( $data->{rows} ) eq 'ARRAY' ) {
        die 'data->rows is not ARRAY';
    }

    my @rows;

    foreach ( @{ $data->{rows} } ) {
        unless ( ref( $_ ) eq 'HASH' ) {
            die 'data->rows[] entry is not HASH';
        }
        unless ( ref( $_->{doc} ) eq 'HASH' ) {
            die 'data->rows[]->doc is not HASH';
        }
        unless ( defined $_->{doc}->{_id} ) {
            die 'data->rows[]->doc->_id is not defined';
        }
        unless ( defined $_->{doc}->{_rev} ) {
            die 'data->rows[]->doc->_rev is not defined';
        }
        push( @rows, { _id => $_->{doc}->{_id}, _rev => $_->{doc}->{_rev} } );
    }

    return \@rows;
}

=item HandleResponseBulk

=cut

sub HandleResponseBulk {
    my ( $self, $cv ) = @_;

    unless ( blessed $cv and $cv->can( 'recv' ) ) {
        die 'cv is not object';
    }

    my $data = $cv->recv;

    unless ( ref( $data ) eq 'ARRAY' ) {
        die 'data is not ARRAY';
    }

    foreach ( @$data ) {
        unless ( ref( $_ ) eq 'HASH' ) {
            die 'data[] is not HASH';
        }
        unless ( defined $_->{id} ) {
            die 'data[]->id is not defined';
        }
        if ( exists $_->{rev} and exists $_->{ok} ) {
            unless ( defined $_->{rev} ) {
                die 'data[]->rev is not defined';
            }
            unless ( defined $_->{ok} ) {
                die 'data[]->ok is not defined';
            }
        }
        elsif ( exists $_->{error} and exists $_->{reason} ) {
            unless ( defined $_->{error} ) {
                die 'data[]->error is not defined';
            }
            unless ( defined $_->{reason} ) {
                die 'data[]->reason is not defined';
            }
        }
        else {
            die 'data[] missing rev/id or error/reason';
        }
    }

    return $data;
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

1;    # End of Lim::Plugin::Zonalizer::DB::CouchDB
