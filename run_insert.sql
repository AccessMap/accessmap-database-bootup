CREATE schema IF NOT EXISTS data;
CREATE schema IF NOT EXISTS build;
SET schema 'data';
/* Required for PostGIS functions to be found while using alt schema */
SET search_path = source, public;
\i /sourcedata/streets.sql
\i /sourcedata/sidewalks.sql
\i /sourcedata/dem.sql
