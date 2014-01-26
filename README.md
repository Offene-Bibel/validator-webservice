Syntaxvalidator to DB bridge
============================

Connect the syntax validator to the SQL database of the wiki.
The following table has to be added. It should suffice for error tracking.

    parse_errors
        INT pageid
        INT revid
        BOOL error_occurred
        VARCHAR error_string


Trigger
-------

I can imagine two different approaches to trigger the validator:

MediaWiki Hooks on page save (push):
- Potentially less load on the site
- Smaller edit -> status update timegap

Time based query mechanism using the recentchanges API (pull):
- Independent -> Breakage can't pull main site down
- Simpler -> No parser related code is in the mediawiki extension
- Safer -> No parser side service required, thus no additional "hole"

https://www.mediawiki.org/wiki/Hooks
https://www.mediawiki.org/wiki/API:Recentchanges
https://www.mediawiki.org/wiki/API:Properties#revisions_.2F_rv
http://www.offene-bibel.de/wiki/api.php5?titles=Genesis_1&action=query&prop=revisions
https://www.mediawiki.org/wiki/API

Display
-------
Realized in the Extension. We add two new tags:

- {{#pagestatus: Genesis_1}}
- [[#status_overview}} (eventuell als Tag)

https://www.mediawiki.org/wiki/Manual:Parser_functions
https://www.mediawiki.org/wiki/Manual:Tag_extensions

http://www.offene-bibel.de/wiki/api.php5?titles=Genesis_1&action=query&prop=revisions&format=json
http://www.offene-bibel.de/wiki/api.php?action=query&list=recentchanges&rcend=20140105101010&rclimit=500&rcprop=title|ids&format=json