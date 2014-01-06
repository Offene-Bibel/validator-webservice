#!/usr/bin/env perl
use v5.12;
use strict;
 
use Dancer2;
 
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
 
dance;

