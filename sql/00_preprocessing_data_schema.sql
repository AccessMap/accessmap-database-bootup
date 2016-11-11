\timing
--
-- Step 0: Create schemas
--
CREATE SCHEMA IF NOT EXISTS source;
CREATE SCHEMA IF NOT EXISTS data;
CREATE SCHEMA IF NOT EXISTS build;

-------------------------------------------------
-- Step 1: Drop all tables created in these steps
-------------------------------------------------
-- TODO: Use DROP with CASCADE?
DROP TABLE IF EXISTS data.curbramps;


--
-- Step 2: Copy relevant keys from source.streets to data.streets
--
-- ALTER TABLE data.streets ADD COLUMN id SERIAL PRIMARY KEY;

CREATE INDEX streets_index
          ON data.streets
       USING gist(geom);

--
-- Step 3: Copy relevant keys from source.sidewalks to data.sidewalks
--

CREATE INDEX sidewalks_index
          ON data.sidewalks
       USING gist(geom);

--
-- Step 5: Infer curb ramp locations from sidewalks dataset
--
CREATE TABLE data.curbramps AS
      SELECT gid AS sw_gid,
	         ST_EndPoint(geom) AS geom
	    FROM data.sidewalks s1
       WHERE s1.curbramp_e = 'Y'
       UNION
      SELECT gid AS sw_gid,
	         ST_StartPoint(geom) AS geom
	    FROM data.sidewalks s2
       WHERE s2.curbramp_s = 'Y';

ALTER TABLE data.curbramps ADD COLUMN gid SERIAL PRIMARY KEY;

CREATE INDEX curbramps_index
          ON data.curbramps
       USING gist(geom);

--
-- Step 6: Convert SRID to same projection as vector data
--
-- FIXME: ST_Transform from 2926 to 26910 produces gaps in the raster data -
--        some kind of per-tile error at the interface between tiles, I think.
--        This screws up using the DEM because those gaps are null-valued and
--        overlap with sidewalks. This seems like a bug in PostGIS/GDAL/libgeos
-- UPDATE data.ned13
--   SET rast = ST_Transform(rast, 26910);

CREATE INDEX ned13_convexhull_index
          ON data.ned13
       USING gist(ST_ConvexHull(rast));

--
-- Drop unnecessary columns
-- ALTER TABLE data.sidewalks DROP COLUMN curbramphi; ALTER TABLE data.sidewalks DROP COLUMN curbramplo;
