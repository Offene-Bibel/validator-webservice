#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use YAML::XS qw( LoadFile );
use DBI;
use Prologue;

my $config = LoadFile( "$FindBin::Bin/../config.yml" );
my $books  = LoadFile( "$FindBin::Bin/../bibleBooks.yml" );
my $dbh = DBI->connect( 'dbi:' . $config->{dbi_url}, $config->{dbi_user}, $config->{dbi_pw} )
    or die "Connection Error: $DBI::errstr\n";

$dbh->do( $_ ) or die "SQL Error: $DBI::errstr\n" for (
'DROP TABLE IF EXISTS bibelwikiofbi_parse_status',
'DROP TABLE IF EXISTS bibelwikiofbi_book',
'DROP TABLE IF EXISTS bibelwikiofbi_chapter',
'DROP TABLE IF EXISTS bibelwikiofbi_verse',
'CREATE TABLE bibelwikiofbi_parse_status ( id INT PRIMARY KEY AUTO_INCREMENT, pageid INT, revid INT, error_occurred BOOL, error_string MEDIUMTEXT )',
'CREATE TABLE bibelwikiofbi_book ( id INT PRIMARY KEY AUTO_INCREMENT, osis_name TINYTEXT, name TINYTEXT, chapter_count INT, part TINYTEXT )',
'CREATE TABLE bibelwikiofbi_chapter ( id INT PRIMARY KEY AUTO_INCREMENT, book_id INT, number INT, verse_count INT )',
'CREATE TABLE bibelwikiofbi_verse ( id INT PRIMARY KEY AUTO_INCREMENT, chapter_id INT, pageid INT, revid INT, version INT, from_number INT, to_number INT, status INT, text MEDIUMTEXT )' );

for my $book ( $books->@* ) {
    $dbh->do( 'INSERT INTO bibelwikiofbi_book VALUES ( NULL, ?, ?, ?, ? );',
        undef,
        (
         $book->{id},
         $book->{name},
         $book->{chapterCount},
         $book->{part}
        )
    ) or die "SQL Error: $DBI::errstr\n";

    my $id = $dbh->last_insert_id( undef, undef, undef, undef );

    my $chapterNo = 1;
    for my $verse ( $book->{verseCounts}->@* ) {
        $dbh->do( 'INSERT INTO bibelwikiofbi_chapter SELECT NULL, id, ?, ? FROM bibelwikiofbi_book WHERE id=?',
            undef,
            (
             $chapterNo,
             $verse,
             $id
            )
        ) or die "SQL Error: $DBI::errstr\n";
        $chapterNo++;
    }
}

