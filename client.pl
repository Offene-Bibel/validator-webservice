#!/usr/bin/env perl
use v5.12;
use strict;
use LWP::UserAgent;
use POSIX qw(strftime);
use DateTime;
use JSON;

my $tracking_file = 'time_tracker';
my $chapter_url = 'http://www.offene-bibel.de/wiki/index.php5?title=%s&action=raw';
my $rc_url = 'http://www.offene-bibel.de/wiki/api.php?action=query&list=recentchanges&rcend=%s&rclimit=500&rcprop=title|ids&format=json';
my $host = 'http://patszim.volans.uberspace.de';
my $port = 63978;

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
# Load proxy settings from environment
$ua->env_proxy;

my @changes = retrieveChanges();
foreach my $change (@changes) {
    my ($status, $desc) = retrieveStatus($change->{page_name}, $host, $port);
    writeToDb($change->{page_id}, $change->{rev_id}, $status, $desc);
}

sub retrieveChanges {
    my $last_rcid;
    if(not -f $tracking_file) {
        $last_rcid = 0; #DateTime->now->substract(days=>1);
    }
    else {
        open my $tracker_fh, "<", $tracking_file;
        #$last_check = DateTime->from_epoch(epoch=><$tracker_fh>);
        $last_rcid = <$tracker_fh>;
        close $tracker_fh;
    }

    my $filled = $rc_url;
    my $timestamp = DateTime->now->substract(days=>1)->strftime("%y%m%d%H%M%S");
    $filled =~ s/%s/$timestamp/;
    my $response = $ua->get($filled);
     
    if ($response->is_success) {
        my @change_list = ();
        my $json = decode_json $response->decoded_content;
        my $end_found = 0;
        foreach my $change (@{$json->{query}->{recentchanges}}) {
            if $change->{rcid} == $last_rcid {
                $end_found = 1;
                last;
            }
            push @change_list {
                page_name => $change->{title},
                page_id => $change->{pageid},
                rev_id => $change->{revid},
            };
        }
        say "Didn't get all diffs." if not $end_found;

        {
            open my $tracker_fh, ">", $tracking_file;
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
    my ($page_name, $host, $port) = @_;
     
    my $filled = $chapter_url;
    my $response = $ua->get("http://$host:$port/validate", 'url' => ($filled =~ s/%s/$page_name/));
     
    if ($response->is_success) {
        my ($returnCode, $errorString) = split /\n/, $response->decoded_content, 2;
        if($returnCode eq 'valid') {
            return ('valid', '');
        } elsif($returnCode eq 'invalid') {
            return ('invalid', $errorString);
        } else {
            return ('server_error', 'Neither valid nor invalid found: '.$returnCode);
        }
    }
    else {
        return ('server_error', 'Status:'.$response->status_line."\nContent:".$response->decoded_content((charset => 'utf-8')));
    }
}

sub writeToDb {
    use DBI;
    my $dbh = DBI->connect('dbi:mysql:perltest','root','password')
        or die "Connection Error: $DBI::errstr\n";
    $sql = "select * from samples";
    $sth = $dbh->prepare($sql);
    $sth->execute
        or die "SQL Error: $DBI::errstr\n";
    while (@row = $sth->fetchrow_array) {
        print "@row\n";
    } 
}

