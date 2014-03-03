create table ofbi_parse_errors (pageid INT, revid INT, error_occurred BOOL, error_string VARCHAR);
create table ofbi_verse (chapterid INT, pageid INT, revid INT, version INT, from_number INT, to_number INT, status INT, text VARCHAR);
create table ofbi_chapter (bookid INT, number INT);
create table ofbi_book (osis_name VARCHAR, name VARCHAR);

