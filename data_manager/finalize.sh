#!/bin/bash

#
# Loads the 'clean' and dem data from the desired city into a database.
#

city=$1
dburi=$2

# Require city argument
if [ -z $city ]; then
    echo "Error: must enter two arguments: city and connection string. Example:"
    echo "'final_cleanup.sh seattle postgres://username:password@localhost:5432/postgres'"
    exit 1
fi

if [ -z $dburi ]; then
    echo "Error: must enter two arguments: city and connection string. Example:"
    echo "'final_cleanup.sh seattle postgres://username:password@localhost:5432/postgres'"
    exit 1
fi

# Load into the database
for sqlfile in sql/*.sql; do
    psql $dburi -f $sqlfile > /dev/null
done
