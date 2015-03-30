#!/usr/bin/env perl
use v5.12;
use strict;
use LWP::UserAgent;
use POSIX qw(strftime);
use DateTime;
use JSON;
use YAML::Any qw{LoadFile};
use URI::Escape;
use File::Slurp;
use DBI;
use Try::Tiny;

my $config_file = 'config.yml';
my $config = LoadFile($config_file);

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
# Load proxy settings from environment
$ua->env_proxy;

print "My PID: $$\n" if $config->{loop_client} eq "true";

my $book_list = LoadFile($config->{book_file});

while (1) {
    my @changes = retrieveChanges();
    foreach my $change (@changes) {
        try {
            my ($status, $desc) = retrieveStatus($change->{page_name}, $config->{host}, $config->{port});
            writeToDb($change->{page_id}, $change->{rev_id}, $status, $desc);
        }
        catch {
            reportError($_);
        }
    }

    last if $config->{loop_client} ne "true";
    if ($config->{loop_minutes} and $config->{loop_minutes} > 0) {
        sleep 60 * $config->{loop_minutes};
    }
    else {
        sleep 60 * 5;
    }
}

sub retrieveChanges {
    my $last_rcid;
    if(not -f $config->{tracking_file}) {
        $last_rcid = 0; #DateTime->now->substract(days=>1);
    }
    else {
        open my $tracker_fh, "<", $config->{tracking_file};
        $last_rcid = <$tracker_fh>;
        close $tracker_fh;
    }

    my $filled = $config->{rc_url};
    my $timestamp = DateTime->now->subtract(days=>1)->strftime("%Y%m%d%H%M%S");
    $filled =~ s/%s/$timestamp/;
    my $response = $ua->get($filled);
     
    if ($response->is_success) {
        my @change_list = ();
        my $json = decode_json $response->decoded_content;
        my $end_found = 0;
        foreach my $change (@{$json->{query}->{recentchanges}}) {
            if ($change->{rcid} == $last_rcid) {
                $end_found = 1;
                last;
            }
            if (is_bible_book($change->{title})) {
                push @change_list, {
                    page_name => $change->{title},
                    page_id => $change->{pageid},
                    rev_id => $change->{revid},
                };
            }
        }
        say "Didn't get all diffs." if not $end_found;

        {
            open my $tracker_fh, ">", $config->{tracking_file};
            print $tracker_fh $json->{query}->{recentchanges}->[0]->{rcid};
            close $tracker_fh;
        }

        return @change_list;
    }
    else {
        die 'Status:'.$response->status_line."\nContent:".$response->decoded_content((charset => 'utf-8'));
    }
}

sub retrieveStatus {
    my $result = $config->{server_mode} eq 'true' ? retrieveStatusViaWeb : retrieveStatusViaLocal;
    my ($returnCode, $data) = split /\n/, $result, 2;
    if($returnCode eq 'valid') {
        return ('valid', $data);
    } elsif($returnCode eq 'invalid') {
        return ('invalid', $data);
    } else {
        die 'Neither valid nor invalid found: ' . $returnCode;
    }
}

sub retrieveStatusViaWeb {
    my ($page_name, $host, $port) = @_;
    my $safe_page_name = uri_escape($page_name);
     
    my $filled = $config->{chapter_url};
    $filled =~ s/%s/$safe_page_name/;
    my $response = $ua->get($config->{host} . ':' . $config->{port} . '/validate', 'url' => $filled);
     
    if ($response->is_success) {
        return $response->decoded_content;
    }
    else {
        die 'server_error Status:' . $response->status_line . "\nContent:" . $response->decoded_content((charset => 'utf-8'));
    }
}


sub retrieveStatusViaLocal {
    my $validator = $config->{validator_path};
    if (not defined $validator or not -x $validator) {
        die 'Validator executable not found.';
    }
    return `$validator -u '$url'`;
}



sub writeToDb {
    my ($page_id, $rev_id, $status, $desc) = @_;
    if($status eq 'valid') {$status = 0}
    else {$status = 1}

    my $dbh = DBI->connect('dbi:'.$config->{dbi_url},$config->{dbi_user},$config->{dbi_pw})
        or die "Connection Error: $DBI::errstr\n";
    my $sql = 'insert into bibelwikiparse_errors values('.$dbh->quote($page_id).', '.$dbh->quote($rev_id).', '.$dbh->quote($status).', '.$dbh->quote($desc).');';
    my $sth = $dbh->prepare($sql);
    $sth->execute
        or die "SQL Error: $DBI::errstr\n";
}

sub is_bible_book {
    my ($potential_name) = @_;
    for my $book (@$book_list) {
        return 1 if ($potential_name  =~ /^$book->{name} \d+$/);
    }
    return 0;
}

sub reportError {
    my $message = shift;

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
     
    Email::Sender::Simple->sendmail($email);
}

