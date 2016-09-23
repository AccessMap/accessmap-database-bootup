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
		     ST_Transform((ST_Dump(geom)).geom, 26910) AS geom
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
		     ST_Transform((ST_Dump(geom)).geom, 26910) AS geom,
		     segkey,
             curbramphi,
             curbramplo
	    FROM source.sidewalks;

ALTER TABLE data.sidewalks ADD COLUMN id SERIAL PRIMARY KEY;

CREATE INDEX sidewalks_index
          ON data.sidewalks
       USING gist(geom);

-- Delete all sidewalks that cause problems when plotting
DELETE FROM data.sidewalks
      WHERE GeometryType(geom) = 'GEOMETRYCOLLECTION';
DELETE FROM data.sidewalks
      WHERE ST_Length(geom) = 0;

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
--
ALTER TABLE data.sidewalks DROP COLUMN curbramphi;
ALTER TABLE data.sidewalks DROP COLUMN curbramplo;

/*
Because of the number (and severity) of errors, it's worthwhile to just
redraw the entire dataset. The strategy used will be to (1) describe each
street as having a sidewalk on the left, right, both, or none sides, then (2)
do a linear offset for the appropriate case, and (3) in the process, trim the
offset so it doesn't overshoot. For step (3), we'll use a buffer of all nearby
streets.
*/

-- First, we need to figure out whether a given sidewalk is on the right or
-- left side of the street
ALTER TABLE data.streets ADD COLUMN sidewalk_l boolean;
ALTER TABLE data.streets ADD COLUMN sidewalk_r boolean;
ALTER TABLE data.streets ADD COLUMN sidewalk_dist float;
UPDATE data.streets
   SET sidewalk_l = false;
UPDATE data.streets
   SET sidewalk_r = false;
UPDATE data.streets
   SET sidewalk_dist = 0;

-- Draw a line from a point on the sidewalk to the nearest part of the street
CREATE TABLE close_vecs AS
SELECT DISTINCT ON (v.sw_id) v.*,
                           -- This calculates the azimuth from sidewalk to street, converts it to radians in a more reasonable coordinate system,
                           -- then uses that to generate an extended line (to help with ST_LineCrossingDirection intersection)
                           ST_AddPoint(v.vec, ST_MakePoint(ST_X(v.vec) + 0.1 * cos(-1 * ST_Azimuth(ST_StartPoint(v.vec), ST_EndPoint(v.vec)) + pi() / 2), 0.1 * sin(-1 * ST_Azimuth(ST_StartPoint(v.vec), ST_EndPoint(v.vec) + pi() / 2)))) AS vec_ext,
                           ST_Length(v.vec::geography) AS dist
                      FROM (SELECT sw.gid AS sw_id,
                                   st.compkey AS st_compkey,
                                   st.geom AS st_geom,
                                   ST_MakeLine(ST_ClosestPoint(sw.geom, st.geom), ST_ClosestPoint(st.geom, sw.geom)) AS vec
                             FROM (SELECT (ST_Dump(ST_Transform(geom, 4326))).*,
                                          gid,
                                          segkey
                                     FROM source.sidewalks) sw
                             JOIN (SELECT (ST_Dump(ST_Transform(geom, 4326))).*,
                                          compkey
                                     FROM source.streets) st
                               ON sw.segkey = st.compkey) v
                  ORDER BY v.sw_id;

UPDATE data.streets
   SET sidewalk_l = true
  FROM close_vecs cv
 WHERE compkey = cv.st_compkey
   AND ST_LineCrossingDirection(cv.vec_ext, st_geom) = -1;

UPDATE data.streets
   SET sidewalk_r = true
  FROM close_vecs cv
 WHERE compkey = cv.st_compkey
   AND ST_LineCrossingDirection(cv.vec_ext, st_geom) = 1;

UPDATE data.streets
   SET sidewalk_dist = a.dist
  FROM (  SELECT min(dist) AS dist,
                 st_compkey
            FROM close_vecs
        GROUP BY st_compkey) a
 WHERE compkey = a.st_compkey;

-- -- Create buffers for every street that has a sidewalk
-- ALTER TABLE data.streets ADD COLUMN buffer geometry;
-- UPDATE data.streets
--    SET buffer = ST_Buffer(geom, sidewalk_dist)
--  WHERE sidewalk_l
--     OR sidewalk_r;
--
-- -- Now draw the sidewalks in
-- CREATE TABLE data.sidewalks2 AS
-- SELECT ST_OffsetCurve(geom, sidewalk_dist) AS geom
--   FROM data.streets
--  WHERE sidewalk_r
--  UNION
-- SELECT ST_OffsetCurve(geom, sidewalk_dist * -1) AS geom
--   FROM data.streets
--  WHERE sidewalk_l;
