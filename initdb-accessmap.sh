#!/bin/sh
set -e

# Perform all actions as user 'postgres'
export PGUSER=postgres

# Import data
psql -d postgres -f /sourcedata/run_insert.sql # > /dev/null
