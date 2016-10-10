-- Step 0: Create index on compkey
-- FIXME: address the problem below early-on (step 0) and require unique
--        identifier
-- TODO: Some of this is run on the raw sidewalks data, but we should use the
--       intersection-fixed sidewalks data
--- compkey (now id) is not unique, so must delete streets with non-unique IDs
-- FIXME: don't modify data.streets at this point - should only modify tables
--        in build schema.
-- DELETE FROM data.streets
--       WHERE id IN (SELECT id
--                      FROM (SELECT id,
--                                   ROW_NUMBER() OVER (partition BY id
--                                                          ORDER BY id) AS rnum
--                              FROM data.streets) AS t
--                     WHERE t.rnum > 1);

CREATE UNIQUE INDEX street_id
                 ON data.streets (id);

-- Step 1: Polygonizing
DROP TABLE IF EXISTS build.blocks CASCADE;

CREATE TABLE build.blocks AS
      SELECT g.path[1] AS id,
             geom
        FROM (SELECT (ST_Dump(ST_Polygonize(streets.geom))).*
      	        FROM data.streets) AS g;

CREATE INDEX boundary_polygons_index
          ON build.blocks
       USING gist(geom);


-- Step 2: Remove overlap polygons
DELETE FROM build.blocks
      WHERE id in (  SELECT b1.id
                       FROM build.blocks b1,
                            build.blocks b2
                      WHERE ST_Overlaps(b1.geom, b2.geom)
                   GROUP BY b1.id
                     HAVING count(b1.id) > 1);

-- There are 57 Polygons that have their centroid outside the polygon.
CREATE VIEW build.weird_blocks AS
     SELECT *
       FROM build.blocks AS b
      WHERE ST_Within(ST_Centroid(b.geom), b.geom) IS False;
