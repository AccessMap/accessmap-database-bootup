DSSG 2016 Sidewalks Project Files
---------------------------------

This repo represents the work done by the 2016 DSSG Sidewalks team in Seattle,
WA, with some later updates for reproducibility.

The primary functionality is to process municipal data for Seattle, which has
many lat-lon inaccuracies (due to the method by which the sidewalk shapes were
generated) into a format that is routable: the sidewalk endpoints are adjusted
to be closer to reality, potential crossing locations are generated from
scratch, and these edges (sidewalks/crossings) are annotated with steepness
(grade) and crossing (curbramps) information.

It is strongly recommended that you use Docker to run this project, as it will
install all of the necessary packages (Postgres/PostGIS/pgrouting, etc),
download all of the source data, and run all of the SQL commands automatically.
If you do not want to use Docker, you can follow the instructions in the
Dockerfile manually in an Ubuntu 14.04/16.04 installation.

Building/Use
------------

1. Build the container:
    docker build .

2. Launch the container:
    docker run --publish 44444:5432 -e POSTGRES_PASSWORD=test <image ID>

You can then access the container at `localhost:44444` with the user `postgres`
and the password `test`. Many other postgres/postgis configuration options
are available, as the base image used is the official postgres image:
https://hub.docker.com/_/postgres/
