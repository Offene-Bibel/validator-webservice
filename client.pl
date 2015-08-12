#!/usr/bin/env perl
use LWP::UserAgent;
use POSIX qw( strftime );
use DateTime;
use JSON;
use YAML qw( LoadFile Load );
use URI::Escape;
use File::Slurp;
use DBI;
use Try::Tiny;
use Prologue;

my $config_file = 'config.yml';
my $config = LoadFile( $config_file );

my $ua = LWP::UserAgent->new;
$ua->timeout( 10 );
# Load proxy settings from environment
$ua->env_proxy;

print "My PID: $$\n" if $config->{loop_client} eq "true";

my $book_list = LoadFile( $config->{book_file} );

while ( 1 ) {
    my @changes = retrieveChanges();
    foreach my $change ( @changes ) {
        try {
            my ( $status, $details ) = retrieveStatus( $change->{page_name}, $config->@{ qw(host port) } );
            writeToDb( $change, $status, $details );
        }
        catch {
            reportError( $_ );
        }
    }

    last if $config->{loop_client} ne "true";
    if ( $config->{loop_minutes} and $config->{loop_minutes} > 0 ) {
        sleep 60 * $config->{loop_minutes};
    }
    else {
        sleep 60 * 5;
    }
}

# Reads in all changes that happened since the last read (or from five days ago when no last read happened).
sub retrieveChanges {
    # Retrieve last recent changes entry we read.
    my $last_rcid;
    if ( not -f $config->{tracking_file} ) {
        $last_rcid = 0; #DateTime->now->substract(days=>1);
    }
    else {
        open my $tracker_fh, "<", $config->{tracking_file};
        $last_rcid = <$tracker_fh>;
        close $tracker_fh;
    }

    # Retrieve the recent changes, going back at most five days.
    my $filled = $config->{rc_url};
    my $timestamp = DateTime->now->subtract( days => 25 )->strftime( "%Y%m%d%H%M%S" );
    $filled =~ s/%s/$timestamp/;
    my $response = $ua->get( $filled );
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
        my $bibleBook = get_bible_book( $change->{title} );
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
        open my $tracker_fh, ">", $config->{tracking_file};
        print $tracker_fh $json->{query}->{recentchanges}->[0]->{rcid};
        close $tracker_fh;
    }

    return @change_list;
}

# Query the parser which tells us whether the given page is valid.
# This can either happen via a web request or directly.
sub retrieveStatus {
    my $result = $config->{server_mode} eq 'true' ? retrieveStatusViaWeb( @_ ) : retrieveStatusViaLocal( @_ );
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
    my ( $page_name, $host, $port ) = @_;
    my $safe_page_name = uri_escape( $page_name );
     
    my $filled = $config->{chapter_url};
    $filled =~ s/%s/$safe_page_name/;
    my $response = $ua->get( $config->{host} . ':' . $config->{port} . '/validate', url => $filled );
     
    if ( $response->is_success ) {
        return $response->decoded_content;
    }
    else {
        die 'server_error Status:' . $response->status_line . "\nContent:" . $response->decoded_content( charset => 'utf-8' );
    }
}

# Query the parser locally.
sub retrieveStatusViaLocal {
    my ( $page_name, $host, $port ) = @_;
    my $safe_page_name = uri_escape( $page_name );
    my $url = $config->{chapter_url};
    $url =~ s/%s/$safe_page_name/;

    my $validator = $config->{validator_path};
    if ( not defined $validator or not -x $validator ) {
        die 'Validator executable not found.';
    }
    say "$validator -u '$url'";
    return `$validator -u '$url'`;
}

# Record a validity status in the database.
sub writeToDb {
    # $change: hash of change info as returned by retrieveStatus
    # $status: valid/invalid
    # $details: either parser error message, or YAML output of parser
    my ( $change, $status, $details ) = @_;
    $status = $status eq 'valid' ? 0 : 1;

    my $dbh = DBI->connect( 'dbi:' . $config->{dbi_url}, $config->{dbi_user}, $config->{dbi_pw} )
        or die "Connection Error: $DBI::errstr\n";
    use Data::Dumper;
    say Dumper( [
         $change->{page_id},
         $change->{rev_id},
         $status,
         $status==0 ? '' : $details
        ] );
=pod
    $dbh->do('insert into bibelwikiparse_errors values(?, ?, ?, ?);',
        undef,
        (
         $change->{page_id},
         $change->{rev_id},
         $status,
         $status==0 ? '' : $details
        )
    ) or die "SQL Error: $DBI::errstr\n";
=cut

    if ( not $status ) {
        my $stati = Load( $details );
        my @chapter_select_result = $dbh->selectrow_array( <<EOS,
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

        for my $verse ( $stati ) {
            say Dumper(
                [
                 $chapterId,        # chapter ID
                 $change->{page_id},# page_id
                 $change->{rev_id}, # rev_id
                 $verse->{version}, # version
                 $verse->{from},    # from_number
                 $verse->{to},      # to_number
                 $verse->{status},  # status
                 $verse->{text},    # text
                ] );
=pod
            $dbh->do(<<EOS,
INSERT INTO bibelwikiparse_verse ( ?, ?, ?, ?, ?, ?, ?, ? )
EOS
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
=cut
        }
    }
}

# Checks the given book name for validity and returns OSIS ID and chapter no if valid.
sub get_bible_book {
    my ( $potential_name ) = @_;
    for my $book ( @$book_list ) {
        if ( $potential_name  =~ /^$book->{name} (\d+)$/ ) {
            return {
                osis_id => $book->{id},
                chapter => $1
            };
        }
    }
    return undef;
}

# Error reporting via email.
sub reportError {
    my $message = shift;
    if ( $config->{error_log_channel} eq 'email' ) {
        try {
            use Email::Sender::Simple;
            use Email::Simple;
            use Email::Simple::Creator;

            my $transport = Email::Sender::Transport::SMTP->new( {
                host => $config->{smtp_host},
                port => $config->{smtp_port},
            } );

            my $email = Email::Simple->create(
              header => [
                To      => '"Patrick Zimmermann" <pzim@posteo.de>',
                From    => '"Offene Bibel validator" <admin@offene-bibel.de>',
                Subject => "Parsing error",
              ],
              body => "$message\n",
            );

            Email::Sender::Simple->send( $email, { transport => $transport } );
        }
        catch {
            reportErrorToFile( "Email send failed: $_\n=============\n$message\n" );
        }
    }
    elsif ( $config->{error_log_channel} eq 'file' ) {
        reportErrorToFile($message);
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

