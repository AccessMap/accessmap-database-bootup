FROM debian:jessie
MAINTAINER Nick Bolten <nbolten@gmail.com>

#
# Install dependencies
#

RUN apt-get update && \
    apt-get install -y \
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
# Install the cli tool
#

WORKDIR /sourcedata
COPY . /sourcedata/data_manager
RUN pip install /sourcedata/data_manager

#
# Set up entrypoint so that container acts like cli app
#

ENTRYPOINT ["data_manager"]
