package OffeneBibel::Validator;
use Moose;
use LWP::UserAgent;
use POSIX qw( strftime );
use DateTime;
use JSON;
use YAML::XS qw( LoadFile Load );
use URI::Escape;
use File::Slurp;
use DBI;
use syntax 'try';
use Encode;
use Prologue;

has 'config' => (
    is => 'rw',
    init_arg => undef # Can't be set by constructor.
);

has 'dbh' => (
    is => 'rw',
    init_arg => undef # Can't be set by constructor.
);

has 'user_agent' => (
    is       => 'rw',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_user_agent'
);
sub _build_user_agent {
    my $ua = LWP::UserAgent->new;
    $ua->timeout( 180 );
    # Load proxy settings from environment
    $ua->env_proxy;
    return $ua;
}

has 'book_list' => (
    is      => 'rw',
);

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->config( LoadFile( $args->{config_file} ));

    my $book_file = $self->config->{book_file};
    if ( ! File::Spec->file_name_is_absolute( $book_file )) {
        my ( $volume, $dirs, undef ) = File::Spec->splitpath( $self->config->{config_file} );
        $book_file = File::Spec->catpath( $volume, $dirs, $book_file );
    }

    $self->book_list( LoadFile( $book_file )); 

    $self->dbh( DBI->connect(
            'dbi:' . $self->config->{dbi_url},
            $self->config->{dbi_user},
            $self->config->{dbi_pw} ))
        or die "Connection Error: $DBI::errstr\n";
}

sub run {
    my $self = shift;
    while ( 1 ) {
        my @changes = $self->retrieveChanges();
        foreach my $change ( @changes ) {
            try {
                my ( $status, $details ) = $self->retrieveStatus( $change->{page_name}, $self->config->@{ qw(host port) } );
                $self->writeToDb( $change, $status, $details );
            }
            catch ( $e ) {
                $self->reportError( $e );
            }
        }

        last if $self->config->{loop_client} ne "true";
        if ( $self->config->{loop_minutes} and $self->config->{loop_minutes} > 0 ) {
            sleep 60 * $self->config->{loop_minutes};
        }
        else {
            sleep 60 * 5;
        }
    }
}

sub full_reparse {
    my $self = shift;

    for my $book ( $self->book_list->@* ) {
    LOOP: for ( my $chapter = 1; $chapter <= $book->{chapterCount}; $chapter++ ) {
    try {
        my $page_name = $book->{name} . '_' . $chapter;
        my $page_info = $self->get_page_info( $page_name );
        if ( $page_info ) {
            my $chapter_info = {
                osis_id   => $book->{id},
                chapter   => $chapter,
                page_id   => $page_info->{pageid},
                rev_id    => $page_info->{revid},
            };

            my ( $status, $details ) = $self->retrieveStatus( $page_name, $self->config->@{ qw(host port) } );
            $self->writeToDb( $chapter_info, $status, $details );
        }
    }
    catch ( $e ) {
        $self->reportError( $e );
    }}}
}

# Reads in all changes that happened since the last read (or from five days ago when no last read happened).
sub retrieveChanges {
    my $self = shift;
    # Retrieve last recent changes entry we read.
    my $last_rcid;
    if ( not -f $self->config->{tracking_file} ) {
        $last_rcid = 0; #DateTime->now->substract(days=>1);
    }
    else {
        open my $tracker_fh, "<", $self->config->{tracking_file};
        $last_rcid = <$tracker_fh>;
        close $tracker_fh;
    }

    # Retrieve the recent changes, going back at most five days.
    my $filled = $self->config->{rc_url};
    my $timestamp = DateTime->now->subtract( days => 25 )->strftime( "%Y%m%d%H%M%S" );
    $filled =~ s/%s/$timestamp/;
    my $response = $self->user_agent->get( $filled );
    die 'Status:' . $response->status_line . "\nContent:" . $response->decoded_content( charset => 'utf-8' ) if not $response->is_success;
     
    # Process recent changes, creating a @change_list.
    my @change_list = ();
    my $json = decode_json( $response->decoded_content );
    my $end_found = 0;
    foreach my $change ( $json->{query}->{recentchanges}->@* ) {
        if ( $change->{rcid} == $last_rcid ) {
            $end_found = 1;
            last;
        }
        my $bibleBook = $self->get_bible_book( $change->{title} );
        if ( $bibleBook ) {
            push @change_list, {
                osis_id   => $bibleBook->{osis_id},
                chapter   => $bibleBook->{chapter},
                page_id   => $change->{pageid},
                rev_id    => $change->{revid},
                page_name => $change->{title},
            };
        }
    }
    say "Didn't get all diffs." if not $end_found;

    # Write the latest recent changes ID back to the tracking file.
    {
        open my $tracker_fh, ">", $self->config->{tracking_file};
        print $tracker_fh $json->{query}->{recentchanges}->[0]->{rcid};
        close $tracker_fh;
    }

    return @change_list;
}

# Query the parser which tells us whether the given page is valid.
# This can either happen via a web request or directly.
sub retrieveStatus {
    my $self = shift;
    my $result = $self->config->{server_mode} ? $self->retrieveStatusViaWeb( @_ ) : $self->retrieveStatusViaLocal( @_ );
    my ( $returnCode, $data ) = split /\n/, $result, 2;
    if ( $returnCode eq 'valid' ) {
        return ( 'valid', $data );
    } elsif ( $returnCode eq 'invalid' ) {
        return ( 'invalid', $data );
    } else {
        die 'Neither valid nor invalid found: ' . $returnCode;
    }
}

# Query the parser via web request.
sub retrieveStatusViaWeb {
    my ( $self, $page_name, $host, $port ) = @_;
    my $safe_page_name = uri_escape( $page_name );
     
    my $filled = $self->config->{chapter_url};
    $filled =~ s/%s/$safe_page_name/;
    my $response = $self->user_agent->get( $self->config->{host} . ':' . $self->config->{port} . '/validate?url=' . uri_escape( $filled ));
     
    if ( $response->is_success ) {
        return $response->decoded_content( charset => 'utf-8' );
    }
    else {
        die 'server_error Status:' . $response->status_line . "\nContent:" . $response->decoded_content( charset => 'utf-8' );
    }
}

# Query the parser locally.
sub retrieveStatusViaLocal {
    my ( $self, $page_name, $host, $port ) = @_;
    my $safe_page_name = uri_escape( $page_name );
    my $url = $self->config->{chapter_url};
    $url =~ s/%s/$safe_page_name/;

    my $validator = $self->config->{validator_path};
    if ( not defined $validator or not -x $validator ) {
        die 'Validator executable not found.';
    }
    return `$validator --json -u '$url'`;
}

# Record a validity status in the database.
sub writeToDb {
    # $change: hash of change info as returned by retrieveChanges
    # $status: valid/invalid
    # $details: either parser error message, or YAML output of parser
    my ( $self, $change, $status, $details ) = @_;
    $status = $status eq 'valid' ? 0 : 1;

    # Insert status.
    $self->dbh->do(
        'DELETE FROM bibelwikiofbi_parse_status WHERE pageid = ? AND revid = ?',
        undef,
        (
         $change->{page_id},
         $change->{rev_id},
        )
    ) or die "SQL Error: $DBI::errstr\n";
    $self->dbh->do(
        'INSERT INTO bibelwikiofbi_parse_status VALUES ( NULL, ?, ?, ?, ? )',
        undef,
        (
         $change->{page_id},
         $change->{rev_id},
         $status,
         $status==0 ? '' : $details
        )
    ) or die "SQL Error: $DBI::errstr\n";

    if ( not $status ) {
        # Insert verse.
        # YAML::XS Load() only accepts UTF-8 octets and always returns decoded Perl strings.
        my $stati = Load( encode( 'UTF-8', $details ) );
        my @chapter_select_result = $self->dbh->selectrow_array( <<EOS,
SELECT bibelwikiofbi_chapter.id
FROM
bibelwikiofbi_book
INNER JOIN
bibelwikiofbi_chapter on bibelwikiofbi_book.id = bibelwikiofbi_chapter.book_id
WHERE bibelwikiofbi_book.osis_name=? AND bibelwikiofbi_chapter.number=?
EOS
            undef,
            (
             $change->{osis_id}, # OSIS book name
             $change->{chapter}, # chapter number
            )
        );
        my $chapterId = $chapter_select_result[0];

        for my $verse ( $stati->@* ) {
            $self->dbh->do(
                'DELETE FROM bibelwikiofbi_verse WHERE pageid = ? AND revid = ?',
                undef,
                (
                 $change->{page_id}, # page_id
                 $change->{rev_id},  # rev_id
                )
            ) or die "SQL Error: $DBI::errstr\n";
            $self->dbh->do(
                'INSERT INTO bibelwikiofbi_verse VALUES ( NULL, ?, ?, ?, ?, ?, ?, ?, ? )',
                undef,
                (
                 $chapterId,         # chapter ID
                 $change->{page_id}, # page_id
                 $change->{rev_id},  # rev_id
                 $verse->{version},  # version
                 $verse->{from},     # from_number
                 $verse->{to},       # to_number
                 $verse->{status},   # status
                 $verse->{text},     # text
                )
            ) or die "SQL Error: $DBI::errstr\n";
        }
    }
}

# Checks the given book name for validity and returns OSIS ID and chapter no if valid.
sub get_bible_book {
    my ( $self, $potential_name ) = @_;
    for my $book ( @{$self->book_list} ) {
        if ( $potential_name  =~ /^$book->{name} (\d+)$/ ) {
            return {
                osis_id => $book->{id},
                chapter => $1
            };
        }
    }
    return undef;
}

sub get_page_info {
    my ( $self, $title ) = @_;
    my $url = $self->config->{meta_url};
    $url =~ s/%s/$title/;

    my $response = $self->user_agent->get( $url );
    die 'Status:' . $response->status_line . "\nContent:" . $response->decoded_content( charset => 'utf-8' ) if not $response->is_success;
    my $json = decode_json( $response->decoded_content );

    my %pages = $json->{query}->{pages}->%*;
    if ( ( scalar keys %pages ) > 1 ) {
        say "More than one page found for title: $title.\n URL: $url\n Skipping.";
        return undef;
    }
    elsif ( ( scalar keys %pages ) == 0 ) {
        say "Pages map returned malformed result. Should have at least one title.\n URL: $url";
        return undef;
    }

    my %first_page = $pages{ (keys %pages)[0] }->%*;
    if ( exists $first_page{missing} ) {
        say "No page found for title: $title.\n URL: $url";
        return undef;
    }

    return {
        pageid => $first_page{pageid},
        revid  => $first_page{lastrevid},
    };
}

# Error reporting via email.
sub reportError {
    my ( $self, $message ) = @_;
    if ( $self->config->{error_log_channel} eq 'email' ) {
        try {
            use Email::Sender::Simple;
            use Email::Simple;
            use Email::Simple::Creator;

            my $email = Email::Simple->create(
              header => [
                To      => '"Patrick Zimmermann" <pzim@posteo.de>',
                From    => '"Offene Bibel validator" <admin@offene-bibel.de>',
                Subject => "Parsing error",
              ],
              body => "$message\n",
            );

            if ( $self->config->{smtp_host} ) {
                my $transport = Email::Sender::Transport::SMTP->new( {
                    host => $self->config->{smtp_host},
                    port => $self->config->{smtp_port} // 25,
                } );
                Email::Sender::Simple->send( $email, { transport => $transport } );
            }
            else {
                Email::Sender::Simple->send( $email );
            }
        }
        catch ( $e ) {
            $self->reportErrorToFile( "Email send failed: $e\n=============\n$message\n" );
        }
    }
    elsif ( $self->config->{error_log_channel} eq 'file' ) {
        $self->reportErrorToFile($message);
    }
    else {
        say STDERR $message;
    }
}

# Log errors to a file. Fallback if email sending fails.
sub reportErrorToFile {
    my $message = shift;
    open my $logFile, '>>', "error.log";
    say $logFile $message;
    close $logFile;
}

1;
