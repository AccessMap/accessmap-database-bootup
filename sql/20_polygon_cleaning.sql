-- Step 0: Create index on compkey
-- FIXME: address the problem below early-on (step 0) and require unique
--        identifier
-- TODO: Some of this is run on the raw sidewalks data, but we should use the
--       intersection-fixed sidewalks data
--- compkey (now id) is not unique, so must delete streets with non-unique IDs
-- FIXME: don't modify data.streets at this point - should only modify tables
--        in build schema.
DELETE FROM data.streets
      WHERE id IN (SELECT id
                     FROM (SELECT id,
                                  ROW_NUMBER() OVER (partition BY id
                                                         ORDER BY id) AS rnum
                             FROM data.streets) AS t
                    WHERE t.rnum > 1);

CREATE UNIQUE INDEX street_id
                 ON data.streets (id);

-- Step 1: Polygonizing
DROP TABLE IF EXISTS build.boundary_polygons CASCADE;

CREATE TABLE build.boundary_polygons AS
      SELECT g.path[1] AS gid,
             geom
        FROM (SELECT (ST_Dump(ST_Polygonize(streets.geom))).*
      	        FROM data.streets) AS g;

CREATE INDEX boundary_polygons_index
          ON build.boundary_polygons
       USING gist(geom);


-- Step 2: Remove overlap polygons
DELETE FROM build.boundary_polygons
      WHERE gid in (  SELECT b1.gid
                        FROM build.boundary_polygons b1,
                             build.boundary_polygons b2
                       WHERE ST_Overlaps(b1.geom, b2.geom)
                    GROUP BY b1.gid
                      HAVING count(b1.gid) > 1);

-- Step1: Find all sidewalks what are within a polygons
DROP TABLE IF EXISTS build.grouped_sidewalks;

CREATE TABLE build.grouped_sidewalks AS SELECT b.gid AS b_id,
                                               s.id AS s_id,
                                               s.geom AS s_geom,
                                               e_changed,
                                               s_changed
                                          FROM data.sidewalks s
                              INNER JOIN build.boundary_polygons b
                                      ON ST_Within(s.geom, b.geom)
                                   WHERE GeometryType(s.geom) = 'LINESTRING';

---  Step2: Find all polygons that is not assigned to any polygons because of offshoots.
UPDATE build.grouped_sidewalks
   SET b_id = query.b_id
  FROM (SELECT b.gid AS b_id,
               s.s_id,
               s.s_geom AS s_geom,
               e_changed,
               s_changed
          FROM (SELECT *
                  FROM build.grouped_sidewalks
                 WHERE b_id IS NULL) AS s
    INNER JOIN build.boundary_polygons AS b
            ON ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5), b.geom) IS True) AS query
 WHERE build.grouped_sidewalks.s_id = query.s_id;

-- highway

--- Not important: For qgis visualization
CREATE VIEW build.correct_sidewalks AS
     SELECT b.gid AS b_id,
            s.s_id,
            ST_MakeLine(ST_Line_Interpolate_Point(s.s_geom, 0.5), ST_Centroid(b.geom)) AS geom
       FROM (SELECT *
               FROM build.grouped_sidewalks
              WHERE b_id IS NULL) AS s
      INNER JOIN build.boundary_polygons AS b
         ON ST_Intersects(s.s_geom, b.geom)
      WHERE ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5), b.geom) IS True;

--- Find a bad polygon(id:666) which looks like a highway.
-- There are 57 Polygons that has centroid outside the polygon. Most of them works well with our algorithm.
CREATE VIEW build.bad_polygons AS
     SELECT *
       FROM build.boundary_polygons AS b
      WHERE ST_Within(ST_Centroid(b.geom), b.geom) IS False;

-- Step 3: Boundaries
-- There are 2779 sidewalks has not been assigned to any polygons
CREATE VIEW build.union_polygons AS
     SELECT q.path[1] AS id,
            geom
       FROM (SELECT (ST_Dump(ST_Union(geom))).*
               -- FIXME: is are the paranthesis before ST_Dump required?
               FROM build.boundary_polygons) AS q;

-- For each unassigned to the closest polygons
UPDATE build.grouped_sidewalks
   SET b_id = query.b_id
  FROM (SELECT DISTINCT ON (s.s_id) s.s_id as s_id,
                                    u.id as b_id
                      FROM (SELECT *
                              FROM build.grouped_sidewalks
                             WHERE b_id IS NULL) AS s
                INNER JOIN build.union_polygons AS u
                        ON u.id=s.b_id
                  ORDER BY s.s_id, ST_Distance(s.s_geom, u.geom)) AS query
 WHERE build.grouped_sidewalks.s_id = query.s_id;
