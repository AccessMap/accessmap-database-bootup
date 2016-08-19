#!/bin/sh
set -e

# Perform all actions as user 'postgres'
export PGUSER=postgres

# Import data
psql -d postgres -f /sourcedata/run_insert.sql # > /dev/null

# Run data cleaning SQL code
for sqlfile in /sourcedata/sql/*; do
    psql -d postgres -f $sqlfile
done
