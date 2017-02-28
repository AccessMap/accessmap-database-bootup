#!/bin/bash

#
# Loads the 'clean' and dem data from the desired city into a database.
#

city=$1
dburi=$2

# Require city argument
if [ -z $city ]; then
    echo "Error: must enter two arguments: city and connection string. Example:"
    echo "'load.sh seattle postgres://username:password@localhost:5432/postgres'"
    exit 1
fi

if [ -z $dburi ]; then
    echo "Error: must enter two arguments: city and connection string. Example:"
    echo "'load.sh seattle postgres://username:password@localhost:5432/postgres'"
    exit 1
fi


# Create output directory if it doesn't exist
sqldir="cities/$city/sql"
if ! [ -d $sqldir ]; then
    mkdir $sqldir
fi

# Run shp2pgsql on all cleaned shapefiles
# FIXME: shouldn't hard-coded projections (26910). Use city settings
#        instead.
for layerpath in cities/$city/clean/*.shp; do
    layer=`basename $layerpath .shp`
    echo "Translating $layer layer to SQL..."
    shp2pgsql -S -s 26910 -d $layerpath $layer > "$sqldir/$layer.sql"
done

# Run rast2pgsql on all DEMs
for dempath in cities/$city/dems/*; do
    demname=`basename $dempath`;
    echo "Translating $demname elevation data to SQL..."
    raster2pgsql -d -t 64x64 $dempath dem.$demname > "$sqldir/dem.$demname.sql"
done

# Load into the database
psql $dburi -c "CREATE SCHEMA IF NOT EXISTS dem;"
for sqlfile in $sqldir/*; do
    table=`basename $sqlfile .sql`
    echo "Creating table $table..."
    # psql $dburi -c "DROP TABLE IF EXISTS $table;"
    psql $dburi -f $sqlfile 1> /dev/null
done
