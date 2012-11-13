neo_crunch
==========

Neo4j and the Crunchbase API mashup

Play with the live version at http://neocrunch.herokuapp.com/
See how it was built at http://wp.me/p26jdv-ow

    git clone https://github.com/maxdemarzi/neo_crunch.git
    cd neo_crunch
    bundle install
    rake neo4j:install
    rake neo4j:start
    rake neo4j:create  (this could take a while)
    rackup

To put this on heroku, you can run neo4j:create to get fresh data, and:

    cd neo_crunch/neo4j/data/graph.db
    zip -r crunchbase.zip *

or use the existing crunchbase.zip with data as of November 12th, 2012.

    heroku apps:create
    heroku addons:add neo4j:try
    git push heroku master

Then go to your Heroku apps https://dashboard.heroku.com/apps/
find your app, and go to your Neo4j add-on.
In the Back-up and Restore section click "choose file",
find the crunchbase.zip file and click submit.
Reload your app to see it running.

