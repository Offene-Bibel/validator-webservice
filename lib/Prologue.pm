package Prologue;

# See https://metacpan.org/pod/Import::Into#WHY-USE-THIS-MODULE

use strict   ();
use warnings ();
use feature  ();
use mro      ();
use utf8     ();
use open     ();
use English  ();

sub import
{
    strict  ->import;

    feature ->import( ':5.20', 'signatures', 'postderef', 'lexical_subs' );
    warnings->import;
    warnings->unimport( 'experimental::signatures',   'experimental::postderef',
                        'experimental::lexical_subs', 'experimental::smartmatch' );
    mro::set_mro( scalar caller(), 'c3' );
    utf8    ->import;
    ::open  ->import( ':encoding(utf8)' );
    binmode STDIN,  ':encoding(utf8)';
    binmode STDOUT, ':utf8';
    binmode STDERR, ':utf8';
    # Get the current locale from the environment, and let STDOUT
    # convert to that encoding:
    #use PerlIO::locale;
    #binmode STDOUT, ':locale';

    my ($target, $file, $line) = caller(1);
    eval "package $target; use English;";
}

1;
