#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use OffeneBibel::Validator;
use Prologue;

my $validator = OffeneBibel::Validator->new( config_file => "$FindBin::Bin/../config.yml" );
$validator->run;

