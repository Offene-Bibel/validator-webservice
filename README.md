Syntaxvalidator Backend
=======================
Basic idea:
Use the parser to validate every wiki page that is edited and display the resulting
status on that wiki page. Also provide a special page to list all pages that fail
to parse.

Limitation:
It is not allowed to run Java programs on the webserver serving the website.

Structure:
Two separate components.
A *client* running on the webserver is polling the wiki to retrieve latest changes.
For every change found a webrequest is sent to the *server* running on a separate
machine. The server downloads the respective page, runs the validator and returns a
result. The *client* then writes that result into the database. The
*Mediawiki extension* reads the data from the database to provide an overview page
and display the tags indicating the status.


Requirements
------------
The following Perl modules are required for the *client*:

- File::Slurp
- YAML::Any
- JSON
- DateTime
- LWP
- DBI
- A DBD::\* driver to talk to the website database (the live website uses mysql)

The *server* requires:
- Dancer2
- The converter (not a Perl module, <https://github.com/Offene-Bibel/converter>)


Design
------

I can imagine two different approaches to trigger the validator:

MediaWiki Hooks on page save (push):
- Potentially less load on the site
- Smaller edit -> status update timegap

Time based query mechanism using the recentchanges API (pull):
- Independent -> Breakage can't pull main site down
- Simpler -> No parser related code is in the mediawiki extension
- Safer -> No parser side service required, thus no additional "hole"

I went for the second approach.


Display
-------
Implemented in the Offene Bibel extension.

- <syntax_status name="Genesis" chapter="1"/>
- {{#syntax_status: Genesis|1}} # This one just forwards the arguments to the <syntax_status> tag.
- {{#syntax_status_overview}}

Links
-----
- <https://www.mediawiki.org/wiki/Hooks>
- <https://www.mediawiki.org/wiki/API:Recentchanges>
- <https://www.mediawiki.org/wiki/API:Properties#revisions_.2F_rv>
- <http://www.offene-bibel.de/wiki/api.php5?titles=Genesis_1&action=query&prop=revisions>
- <https://www.mediawiki.org/wiki/API>
- <https://www.mediawiki.org/wiki/Manual:Parser_functions>
- <https://www.mediawiki.org/wiki/Manual:Tag_extensions>
- <http://www.offene-bibel.de/wiki/api.php5?titles=Genesis_1&action=query&prop=revisions&format=json>
- <http://www.offene-bibel.de/wiki/api.php?action=query&list=recentchanges&rcend=20140105101010&rclimit=500&rcprop=title|ids&format=json>

