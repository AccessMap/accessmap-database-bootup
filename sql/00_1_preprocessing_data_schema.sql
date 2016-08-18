\timing
-------------------------------------------------
-- Step 1: Drop all tables created in these steps
-------------------------------------------------
-- TODO: Use DROP with CASCADE?
DROP TABLE IF EXISTS data.streets;
DROP TABLE IF EXISTS data.sidewalks;
DROP TABLE IF EXISTS data.curbramps;


--
-- Step 2: Copy relevant keys from source.streets to data.streets
--
-- FIXME: compkey (id in 'streets') is not unique, but it gets used later. Should be
--        renamed and if a unique id is needed, it should be created on that
--        data set
-- TODO: investigate SRID of geom
CREATE TABLE data.streets AS
      SELECT compkey,
             -- FIXME: LineMerge has undesired behavior of stitching together
             -- MultiLineStrings (makes new connections) - instead, explode
             -- MultiLineStrings into new rows of LineStrings
		     ST_Transform((ST_Dump(geom)).geom, 2926) AS geom
	    FROM source.streets;
ALTER TABLE data.streets ADD COLUMN id SERIAL PRIMARY KEY;

CREATE INDEX streets_index
          ON data.streets
       USING gist(geom);

--
-- Step 3: Copy relevant keys from source.sidewalks to data.sidewalks
--
-- Transform sidewalks data from SDOT
CREATE TABLE data.sidewalks AS
      SELECT compkey,
		     ST_Transform((ST_Dump(geom)).geom, 2926) AS geom,
		     segkey,
             curbramphi,
             curbramplo
	    FROM source.sidewalks;
ALTER TABLE data.sidewalks ADD COLUMN id SERIAL PRIMARY KEY;

CREATE INDEX sidewalks_index
          ON data.sidewalks
       USING gist(geom);

-- Delete all sidewalks that cause problems when plotting
-- FIXME: Fix ST_LineMerge errors and avoid deleting null sidewalks
DELETE FROM data.sidewalks
      WHERE GeometryType(geom) = 'GEOMETRYCOLLECTION';

-- Add new column to record the state of starting point and ending post of the sidewalk
ALTER TABLE data.sidewalks
 ADD COLUMN "s_changed" BOOLEAN DEFAULT FALSE,
 ADD COLUMN "e_changed" BOOLEAN DEFAULT FALSE;


--
-- Step 5: Infer curb ramp locations from sidewalks dataset
--
CREATE TABLE data.curbramps AS
      SELECT compkey AS sw_compkey,
	         ST_EndPoint(geom) AS geom
	    FROM data.sidewalks s1
       WHERE s1.curbramphi = 'Y'
       UNION
      SELECT compkey AS sw_compkey,
	         ST_StartPoint(geom) AS geom
	    FROM data.sidewalks s2
       WHERE s2.curbramplo = 'Y';
ALTER TABLE data.curbramps ADD COLUMN id SERIAL PRIMARY KEY;

CREATE INDEX curbramps_index
          ON data.curbramps
       USING gist(geom);

--
-- Step 6: Convert SRID to same as vector data
--
UPDATE data.ned13
   SET rast = ST_Transform(rast, 2926);

CREATE INDEX ned13_convexhull_index
          ON data.ned13
       USING gist(ST_ConvexHull(rast));

--
-- Drop unnecessary columns
--
ALTER TABLE data.sidewalks DROP COLUMN curbramphi;
ALTER TABLE data.sidewalks DROP COLUMN curbramplo;
