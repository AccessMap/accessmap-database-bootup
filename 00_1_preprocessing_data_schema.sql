\timing
-- Input --> outputs:
--      v_streets (SDOT streets) --> streets
--          compkey --> id, ST_LineMerge(wkb_geometry) --> geom
--
--      v_sidewalks (SDOT sidewalks) --> sidewalks
--

-- FIXME: segkey is kept for sidewalks, is not going to exist for most other
--        cities. Work around needing it.


-------------------------------------------------
-- Step 1: Drop all tables created in these steps
-------------------------------------------------
-- TODO: Use DROP with CASCADE?
DROP TABLE IF EXISTS data.streets;
DROP TABLE IF EXISTS data.sidewalks;
DROP TABLE IF EXISTS data.curbramps;


-----------------------------------
-- Step 2: Copy relevant keys from v_streets to streets
-----------------------------------
-- FIXME: compkey (id in 'streets') is not unique, but it gets used later. Should be
--        renamed and if a unique id is needed, it should be created on that
--        data set
-- TODO: investigate SRID of geom
CREATE TABLE data.streets AS
      SELECT compkey AS id,
             -- FIXME: LineMerge has undesired behavior of stitching together
             -- MultiLineStrings (makes new connections) - instead, explode
             -- MultiLineStrings into new rows of LineStrings
		     ST_LineMerge(wkb_geometry) AS geom
	    FROM source.v_streets;

CREATE INDEX streets_index
          ON data.streets
       USING gist(geom);


-----------------------------------------------------------
-- Step 3: Copy relevant keys from v_sidewalks to sidewalks
-----------------------------------------------------------
--- Transform sidewalks data from SDOT
CREATE TABLE data.sidewalks AS
      SELECT compkey AS id,
		     ST_LineMerge(ST_Transform(wkb_geometry, 2926)) AS geom,
		     segkey
	    FROM source.v_sidewalks;

CREATE INDEX sidewalks_index
          ON data.sidewalks
       USING gist(geom);

ALTER TABLE data.sidewalks
        ADD PRIMARY KEY (id);

-- Delete all sidewalks that cause problems when plotting
-- FIXME: Fix ST_LineMerge errors and avoid deleting null sidewalks
DELETE FROM data.sidewalks
      WHERE GeometryType(geom) = 'GEOMETRYCOLLECTION';

-- Add new column to record the state of starting point and ending post of the sidewalk
ALTER TABLE data.sidewalks
 ADD COLUMN "s_changed" BOOLEAN DEFAULT FALSE,
 ADD COLUMN "e_changed" BOOLEAN DEFAULT FALSE;


-----------------------------------
-- Step 5: Copy relevant keys from source.v_curbramps to data.curbramps
-----------------------------------
CREATE TABLE data.curbramps AS
      SELECT cast(segkey as integer) AS id,
             -- FIXME: LineMerge has undesired behavior of stitching together
             -- MultiLineStrings (makes new connections) - instead, explode
             -- MultiLineStrings into new rows of LineStrings
	         geom
	    FROM source.v_curbramps;

CREATE INDEX curbramps_index
          ON data.curbramps
       USING gist(geom);
