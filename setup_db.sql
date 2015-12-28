SQLite
======

    create table bibelwikiofbi_parse_errors (pageid INT, revid INT, error_occurred BOOL, error_string VARCHAR);
    create table bibelwikiofbi_verse (chapterid INT, pageid INT, revid INT, version INT, from_number INT, to_number INT, status INT, text VARCHAR);
    create table bibelwikiofbi_chapter (bookid INT, number INT);
    create table bibelwikiofbi_book (osis_name VARCHAR, name VARCHAR);

MySQL/MariaDB
=============

    create table bibelwikiofbi_parse_errors (pageid INT, revid INT, error_occurred BOOL, error_string MEDIUMTEXT);
    create table bibelwikiofbi_verse (chapterid INT, pageid INT, revid INT, version INT, from_number INT, to_number INT, status INT, text MEDIUMTEXT);
    create table bibelwikiofbi_chapter (bookid INT, number INT);
    create table bibelwikiofbi_book (osis_name TINYTEXT, name TINYTEXT);

