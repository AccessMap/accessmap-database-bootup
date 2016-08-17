FROM starefossen/pgrouting:9.4-2.1-2.1
MAINTAINER Nick Bolten <nbolten@gmail.com>

RUN apt-get update && \
    apt-get install -y \
      curl \
      unzip

# Location for source data - used during container deployment
RUN mkdir -p /sourcedata/{Streets,Sidewalks}

# Download, unzip, and create SQL dump for street centerline data from
# data.seattle.gov
WORKDIR /sourcedata/Streets
RUN curl -L -o streets.zip \
      https://data.seattle.gov/download/afip-2mzr/application%2Fzip && \
    unzip streets.zip
RUN shp2pgsql -s 4326 -d WGS84/Street_Network_Database.shp source.streets > \
      /sourcedata/streets.sql

# Download, unzip, and create SQL dump for street centerline data from
# data.seattle.gov
WORKDIR /sourcedata/Sidewalks
RUN curl -L -o sidewalks.zip \
     https://data.seattle.gov/api/assets/038178CC-C40F-4FD2-912C-1E1CF2602D00?download=true && \
    unzip sidewalks.zip
RUN shp2pgsql -s 2926 -d Sidewalks/Sidewalks.shp sidewalks > \
      /sourcedata/sidewalks.sql

# Files in the initdb.d directory get executed in alphabetical order -
# 'routing.sh' is already present from pgrouting, so we have to run just after
# that. The data is loaded during container deployment, not built-in, following
# postgres docker container standards.
COPY ./initdb-accessmap.sh /docker-entrypoint-initdb.d/setup_accessmap.sh
COPY ./run_insert.sql /sourcedata/run_insert.sql
