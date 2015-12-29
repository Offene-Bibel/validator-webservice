#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer2;
use Prologue;
 
get '/validate' => sub {
    my $url = request->header('url');
    if (not defined $url) {
        status 400; # bad_request
        return "No 'url' parameter given.";
    }

    my $validator = config->{validator_path};
    if (not defined $validator or not -x $validator) {
        status 500; # Internal Server Error
        return 'Validator executable not found.';
    }

    my $result = `$validator -u '$url'`;
    return $result;
};  
 
to_app;
