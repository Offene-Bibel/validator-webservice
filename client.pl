#!/usr/bin/env perl

require LWP::UserAgent;
 
my $ua = LWP::UserAgent->new;
$ua->timeout(10);

# Load proxy settings from environment
$ua->env_proxy;
 
my $response = $ua->get('http://localhost:63978/validate', 'url' => 'http://www.offene-bibel.de/wiki/index.php5?action=raw&title=Psalm_23');
 
if ($response->is_success) {
    print $response->decoded_content;  # or whatever
}
else {
    die $response->decoded_content((charset => 'utf-8')); #$response->status_line;
}

