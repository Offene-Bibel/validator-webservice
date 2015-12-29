Syntaxvalidator Backend
=======================

A script to check all changed chapter pages on <http://offene-bibel.de/> through a parser and syntax checker and write the results (syntax ok/failure + text of all verses) to a database. The syntax status is displayed on the website. Verse text might be used later on.


Installation
------------

It is recommended to use [plenv](https://github.com/tokuhirom/plenv) and [carton](https://metacpan.org/pod/Carton) for dependency management.

    # Install plenv
    git clone https://github.com/tokuhirom/plenv.git ~/.plenv
    echo 'export PATH="$HOME/.plenv/bin:$PATH"' >> ~/.bash_profile
    echo 'eval "$(plenv init -)"' >> ~/.bash_profile
    exec $SHELL -l
    git clone https://github.com/tokuhirom/Perl-Build.git ~/.plenv/plugins/perl-build/

    # Install Perl + cpanm + Carton
    plenv install 5.22.1 # Use the version specified in the .perl-version file.
    plenv shell 5.22.1
    plenv install-cpanm
    cpanm Carton
    plenv rehash

    # Install the validator backend
    git clone https://github.com/Offene-Bibel/validator-webservice.git
    cd validator-webservice
    carton install

Finally install the Java-based Converter as decribed on its [website](https://github.com/Offene-Bibel/converter).


Running
-------

To start the *server* use the following command:

    carton exec local/bin/plackup -p 12345 bin/server.psgi

To start the *client* use the following command:

    carton exec bin/client.pl


Motivation
----------

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

