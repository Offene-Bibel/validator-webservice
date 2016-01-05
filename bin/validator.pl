#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Lucid qw( :all );
use OffeneBibel::Validator;
use Prologue;

my $options = Getopt::Lucid->getopt( [
    Switch( 'full-reparse|f' ),
    Switch( 'help|h' ),
])->validate;

if( $options->get_help ) {
    say <<EOT
Usage: $PROGRAM_NAME [--help|-h] [--full-reparse|-f]
  --help
  -h      Display this help mesage.
  --full-reparse
  -f      Process the latest revision of all chapters and exit.
EOT
}
elsif( $options->get_full_reparse ) {
    my $validator = OffeneBibel::Validator->new( config_file => "$FindBin::Bin/../config.yml" );
    $validator->full_reparse;
}
else {
    my $validator = OffeneBibel::Validator->new( config_file => "$FindBin::Bin/../config.yml" );
    $validator->run;
}

