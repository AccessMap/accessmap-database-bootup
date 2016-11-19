#!/bin/bash

# Operate in the data_manager directory
cd data_manager

# Set up Seattle as the example city
cp -r example_city cities/seattle

# Create an empty database (note: you need to kill + rm it to re-run this
# command)
docker run -d --name accessmapdb -p 44444:5432 -e POSTGRES_PASSWORD=test -e PGDATA=/var/lib/postgresql/data/pgdata -v $(pwd)/pgsql_data:/var/lib/postgresql/data/pgdata starefossen/pgrouting:9.4-2.1-2.1

# Download + clean the data
docker build --tag dm . && docker run -v $(pwd):/sourcedata dm all seattle

# Load the data into the database
docker run -it --link accessmapdb -v $(pwd):/wd -w /wd starefossen/pgrouting:9.4-2.1-2.1 sh ./load.sh seattle postgres://postgres:test@accessmapdb:5432/postgres

# Finish up cleaning + do pgRouting graph prep
docker run -it --link accessmapdb -v $(pwd):/wd -w /wd starefossen/pgrouting:9.4-2.1-2.1 sh ./final_cleanup.sh seattle postgres://postgres:test@accessmapdb:5432/postgres
