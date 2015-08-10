package Prologue;

use strict;
use warnings ();
use feature  ();
use mro      ();
use utf8;

sub import
{
    strict  ->import;
    feature ->import( ':5.20', 'signatures', 'postderef', 'lexical_subs' );
    warnings->import;
    warnings->unimport( 'experimental::signatures',
'experimental::postderef',
                        'experimental::lexical_subs',
'experimental::smartmatch' );
    mro::set_mro( scalar caller(), 'c3' );
    utf8    ->import;
}

1;
