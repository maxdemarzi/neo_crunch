neo_crunch
==========

Neo4j and the Crunchbase API mashup

    cd neo_crunch/neo4j/data/graph.db
    zip -r crunchbase.zip *

    heroku apps:create neocrunch
    heroku addons:add neo4j:try
    git push heroku master

Then go to your Heroku apps https://dashboard.heroku.com/apps/
find your app, and go to your Neo4j add-on.
In the Back-up and Restore section click "choose file",
find the crunchbase.zip file and click submit.

