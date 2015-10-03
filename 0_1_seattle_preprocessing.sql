\timing
-- Input --> outputs:
--      v_streets (SDOT streets) --> streets
--          compkey --> id, ST_LineMerge(wkb_geometry) --> geom
--     streets --> intersections (via algorithms)
--
--      v_sidewalks (SDOT sidewalks) --> sidewalks
--

-- FIXME: segkey is kept for sidewalks, is not going to exist for most other
--        cities. Work around needing it.


-------------------------------------------------
-- Step 1: Drop all tables created in these steps
-------------------------------------------------
-- TODO: Use DROP with CASCADE?
DROP TABLE IF EXISTS streets;
DROP TABLE IF EXISTS sidewalks;
DROP TABLE IF EXISTS intersections;
DROP TABLE IF EXISTS curbramps;


-----------------------------------
-- Step 2: Copy relevant keys from v_streets to streets
-----------------------------------
-- FIXME: compkey (id in 'streets') is not unique, but it gets used later. Should be
--        renamed and if a unique id is needed, it should be created on that
--        data set
-- TODO: investigate SRID of geom
CREATE TABLE streets AS SELECT compkey AS id,
                               -- FIXME: LineMerge has undesired behavior of stitching together
                               -- MultiLineStrings (makes new connections) - instead, explode
                               -- MultiLineStrings into new rows of LineStrings
		                       ST_LineMerge(wkb_geometry) AS geom
	                      FROM v_streets;

CREATE INDEX streets_index
          ON streets
       USING gist(geom);


-----------------------------------------------------------
-- Step 3: Copy relevant keys from v_sidewalks to sidewalks
-----------------------------------------------------------
--- Transform sidewalks data from SDOT
CREATE TABLE sidewalks AS SELECT compkey AS id,
		                         ST_LineMerge(ST_Transform(wkb_geometry, 2926)) AS geom,
		                         segkey
	                        FROM v_sidewalks;

CREATE INDEX sidewalks_index
          ON sidewalks
       USING gist(geom);

ALTER TABLE sidewalks
        ADD PRIMARY KEY (id);

-- Delete all sidewalks that cause problems when plotting
-- FIXME: Fix ST_LineMerge errors and avoid deleting null sidewalks
DELETE FROM sidewalks
      WHERE GeometryType(geom) = 'GEOMETRYCOLLECTION';

-- Add new column to record the state of starting point and ending post of the sidewalk
ALTER TABLE sidewalks
 ADD COLUMN "s_changed" BOOLEAN DEFAULT FALSE,
 ADD COLUMN "e_changed" BOOLEAN DEFAULT FALSE;


--------------------------------------------
-- Step 4: Create intersections from streets
--------------------------------------------
--- Find intersection point from street
-- Note: For each intersection, the street id, points and degree is sorted in clock-wise order.
CREATE TABLE intersections AS SELECT row_number() over() AS id,
		                             geom,
		                             array_agg(s_id) AS s_id,
		                             array_agg(other) AS s_others,
		                             array_agg(degree) AS degree,
		                             count(id) AS num_s
	                     FROM (SELECT *,
			                          row_number() over() AS id
		                         FROM (SELECT ST_PointN(p.geom, 1) AS geom,
				                              id AS s_id,
				                              ST_PointN(p.geom, 2) AS other,
				                              ST_Azimuth(ST_PointN(p.geom, 1), ST_PointN(p.geom, 2)) AS degree
			                             FROM streets AS p
                                        UNION
                                       SELECT ST_PointN(p.geom,ST_NPoints(p.geom)) AS geom,
				                              id AS s_id,
				                              ST_PointN(p.geom,ST_NPoints(p.geom) - 1) AS other,
				                              ST_Azimuth(ST_PointN(p.geom, ST_NPoints(p.geom)), ST_PointN(p.geom,ST_NPoints(p.geom) - 1)) AS degree
			                             FROM streets AS p) AS q
		                      ORDER BY geom, st_azimuth(q.geom, q.other)) AS q2
	                 GROUP BY geom;

CREATE INDEX intersections_index
          ON intersections
       USING gist(geom);

ALTER TABLE intersections
        ADD PRIMARY KEY (id);

-----------------------------------
-- Step 5: Copy relevant keys from v_curbramps to curbramps
-----------------------------------
CREATE TABLE curbramps AS SELECT segkey AS id,
                               -- FIXME: LineMerge has undesired behavior of stitching together
                               -- MultiLineStrings (makes new connections) - instead, explode
                               -- MultiLineStrings into new rows of LineStrings
		                       ST_LineMerge(wkb_geometry) AS geom
	                      FROM v_curbramps;

CREATE INDEX curbramps_index
          ON curbramps
       USING gist(geom);
