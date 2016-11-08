FROM starefossen/pgrouting:9.4-2.1-2.1
MAINTAINER Nick Bolten <nbolten@gmail.com>

RUN apt-get update && \
    apt-get install -y \
      curl \
      cython \
      gdal-bin \
      libgdal-dev \
      libspatialindex-dev \
      python-dev \
      python-gdal \
      python-pandas \
      python-pip \
      python-shapely \
      unzip

RUN pip install geopandas==0.2.1 rtree==0.8.2

#
# Download and extract data from data.seattle.gov
#

# Street centerlines
WORKDIR /sourcedata/streets
RUN curl -L -o streets.zip \
      https://data.seattle.gov/download/afip-2mzr/application%2Fzip && \
    unzip streets.zip

# Sidewalk centerlines
WORKDIR /sourcedata/sidewalks
RUN curl -L -o sidewalks.zip \
     https://data.seattle.gov/api/assets/038178CC-C40F-4FD2-912C-1E1CF2602D00?download=true && \
    unzip sidewalks.zip

#
# Download and extract data from USGS (raster elevation)
#

WORKDIR /sourcedata/dem
RUN curl -O https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/ArcGrid/n48w123.zip && \
    unzip ./n48w123.zip && \
    raster2pgsql -t 64x64 grdn48w123_13/w001001.adf data.ned13 > /sourcedata/dem.sql

#
# Clean/fix the sidewalk data (Python)
#

COPY ./fix_sidewalks /sourcedata/fix_sidewalks
COPY ./workflow.py /sourcedata/workflow.py
WORKDIR /sourcedata
RUN python workflow.py \
      streets/StatePlane/Street_Network_Database.shp \
      sidewalks/Sidewalks/Sidewalks.shp

#
# Integrate sidewalk data into PostGIS, create street crossings, routing
# network, etc
#

# RUN shp2pgsql -s 4326 -d clean/streets.shp source.streets > \
#       /sourcedata/streets.sql
# # shp2pgsql took forever to use 'DROP IF EXISTS'
# # (https://trac.osgeo.org/postgis/ticket/2236)
# RUN sed -i 's/DROP TABLE/DROP TABLE IF EXISTS/g' /sourcedata/streets.sql
# # shp2pgsql also tries to drop a geometry column from a nonexistent table
# RUN sed -i '/DropGeometryColumn/d' /sourcedata/streets.sql
#
# RUN shp2pgsql -s 2926 -d clean/sidewalks.shp sidewalks > \
#       /sourcedata/sidewalks.sql
# RUN sed -i 's/DROP TABLE/DROP TABLE IF EXISTS/g' /sourcedata/sidewalks.sql
# RUN sed -i '/DropGeometryColumn/d' /sourcedata/sidewalks.sql
#
# # Files in the initdb.d directory get executed in alphabetical order -
# # 'routing.sh' is already present from pgrouting, so we have to run just after
# # that. The data is loaded during container deployment, not built-in, following
# # postgres docker container standards.
# COPY ./run_insert.sql /sourcedata/run_insert.sql
# COPY ./sql /sourcedata/sql
# COPY ./initdb-accessmap.sh /docker-entrypoint-initdb.d/setup_accessmap.sh
