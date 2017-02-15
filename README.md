AccessMap Database Bootup
=========================

Automated builds of AccessMap Seattle's database. Used for development and
testing and won't currently work for other cities, but is getting there.

Using this repository
---------------------

This repository contains a command-line tool, `data_manager`, for fetching and
cleaning the data, and two bash scripts for loading that data into the database
and running final cleaning steps (`load.sh` and `finalize.sh`,
respectively).

These scripts can be run directly on a host computer that has the right
dependencies (Python packages and postgres + PostGIS + pgRouting). In addition,
we document a Docker-based version that requires no installation of software
(aside from docker) and creates a portable database. Note that there is a
city configuration file in `example_city/sources.json`. This is meant to model
the configuration parameters that may vary from city to city, and is used by
this workflow, but is not yet extensible to other cities.

#### Directly running the scripts

1. Install postgres and enable PostGIS and pgRouting on your database of
choice.

2. Install all necessary Python dependencies (optionally using virtualenv).
Note: `data_manager` is written for Python 2, but will probably run in Python 3
as well. The dependencies are listed in `data_manager/requirements.txt`.

3. (optional) install data_manager
`data_manager` can be run directly by running `python -m data_manager` in its
directory. It can also be installed with `pip`: `pip install ./data_manager` in
the main repo directory. Replace `data_manager` with `python -m data_manager`
in all following commands, if you don't install it with `pip`.

4. Run these commands, in order, starting in the `data_manager` directory:

`cp -r example_city cities/seattle`: Copies the configuration files to the
appropriate 'build' directory.

`data_manager all seattle`: Carries out all steps of the workflow, in order:
`fetch` (download geometries), `dem` (download elevation data),
`standardize` (standardize column names), `clean` (fix data points).

`sh ./load.sh seattle postgres://user:password@host:port/database`, where the
database URI has the appropriate variables fill in for your database.

`sh ./finalize.sh seattle postgres://user:password@host:port/database`

There you go! An exact copy of AccessMap's database, ready for routing.


#### Running with Docker

Note: you can run all of the following commands with `sh workflow.sh`.

Note: You will probably need to completely refresh the database before
re-running any of the commands (delete `pgsql_data`).

1. Change to the `data_manager` directory
`cd data_manager`

2. Copy the configuration file
`cp -r example_city cities/seattle`

3. Run a PostGIS + pgRouting-enabled database
`docker run -d --name accessmapdb -p 44444:5432 -e POSTGRES_PASSWORD=test -e PGDATA=/var/lib/postgresql/data/pgdata -v $(pwd)/pgsql_data:/var/lib/postgresql/data/pgdata starefossen/pgrouting:9.4-2.1-2.1`

Note that it's available on your local machine at port 44444 for testing. In
addition, it is persistently mounted at your current directory in the
`pgsql_data` subdirectory.

4. Run the `data_manager` commands
`docker build --tag dm . && docker run -v $(pwd):/sourcedata dm all seattle`

Note: if you get a `can't stat` error regarding the directory containing our
database (by default pgsql_data), this means docker is trying to read that
directory and failing as your user, which lacks permissions to do so. You can
add that directory to the .dockerignore file until this issue is fixed.

5. Load the data into the database
`docker run -it --link accessmapdb -v $(pwd):/wd -w /wd starefossen/pgrouting:9.4-2.1-2.1 sh ./load.sh seattle postgres://postgres:test@accessmapdb:5432/postgres`

Note: you may see errors about `table <table> does not exist`. This is a bug in
shp2pgsql and normal - the table will be correctly created.

6. Finalize the database (cleanup + pgrouting table)
`docker run -it --link accessmapdb -v $(pwd):/wd -w /wd starefossen/pgrouting:9.4-2.1-2.1 sh ./final_cleanup.sh seattle postgres://postgres:test@accessmapdb:5432/postgres`

7. The container has been created, so if you restart or otherwise stop the container, it can be restarted any time, from any directory, by running `docker start accessmapdb`.
