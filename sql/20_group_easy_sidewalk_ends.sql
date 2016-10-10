/*
Assign sidewalk ends to their closest intersection that's within a given
tolerance.
*/

DROP TABLE IF EXISTS build.ixn_grouped_ends;

CREATE TABLE build.ixn_grouped_ends AS
  SELECT DISTINCT ON (sw_ends.geom)
         sw_ends.geom AS end_geom,
         i.geom AS ixn_geom,
         i.id AS ixn_id,
         sw_ends.id AS sw_id,
         sw_ends.endtype,
         ST_Distance(sw_ends.geom, i.geom) AS dist
    FROM (SELECT id,
                 ST_StartPoint(geom) AS geom,
                 'start' AS endtype
            FROM data.sidewalks
           UNION
          SELECT id,
                 ST_EndPoint(geom) AS geom,
                 'end' AS endtype
            FROM data.sidewalks) sw_ends
    JOIN build.intersections i
      ON ST_DWithin(sw_ends.geom, i.geom, 20)
ORDER BY sw_ends.geom, dist;


--
-- Create a table of sidewalk ends that includes the total count that
-- were grouped together.
--

CREATE INDEX block_index
          ON build.blocks
       USING gist(geom);

CREATE TABLE ixn_circles AS
SELECT ST_Buffer(geom, 20) AS geom,
       id AS ixn_id
  FROM build.intersections;

CREATE INDEX circ_index
          ON ixn_circles
       USING gist(geom);

--
-- Per-intersection, create a circle and split it into block pieces. e.g.
-- a 4-way intersection will have 4 'pie slices' for sorting out which
-- sidewalk endpoints should be considered candidates for merging
--

CREATE TABLE ixn_circles_by_block AS
SELECT ST_Intersection(circs.geom, b.geom) AS geom,
       row_number() over() AS id,
       circs.ixn_id,
       b.id AS block_id
  FROM ixn_circles circs
  JOIN build.blocks b
    ON ST_Intersects(circs.geom, b.geom);

-- CREATE TABLE ixn_streets AS
--   SELECT ST_Collect(st.geom) AS geom_collection,
--          s.ixn_id
--     FROM (SELECT unnest(s_id) AS s_id,
--                  id AS ixn_id
--             FROM build.intersections) s
--     JOIN data.streets st
--       ON st.id = s.s_id
-- GROUP BY s.ixn_id;

-- CREATE TABLE ixn_circles_by_block AS
-- SELECT (ST_Dump(ST_Split(circs.geom, s.geom_collection))).geom AS geom,
--        row_number() over() AS id,
--        circs.ixn_id
--   FROM ixn_circles circs
--   JOIN ixn_streets s
--     ON s.ixn_id = circs.ixn_id;

ALTER TABLE ixn_circles_by_block
        ADD PRIMARY KEY (id);

--
-- Group the sidewalk ends by intersection + block (using circle pieces from
-- 'ixn_circles_by_block'
--

CREATE TABLE circle_block_grouped_ends AS
SELECT i.sw_id,
       i.ixn_id,
       i.endtype,
       i.end_geom,
       c.id AS circle_id,
       c.block_id
  FROM build.ixn_grouped_ends i
  JOIN ixn_circles_by_block c
    ON i.ixn_id = c.ixn_id
   AND ST_Within(i.end_geom, c.geom);

CREATE TEMPORARY TABLE ixn_counted AS
  SELECT count(*) AS end_count,
         circle_id
    FROM circle_block_grouped_ends
GROUP BY circle_id;

ALTER TABLE circle_block_grouped_ends ADD COLUMN end_count integer;

UPDATE circle_block_grouped_ends c
   SET end_count = i.end_count
  FROM ixn_counted i
 WHERE c.circle_id = i.circle_id;

--
-- Fix the grouped sidewalk ends, flag the groups with 1 or 2 as 'fixed'
--

-- ALTER TABLE circle_block_grouped_ends c ADD COLUMN fixed boolean DEFAULT false;
--
--  SELECT c2.circle_id,
--
--    FROM (SELECT sw_id,
--                 endtype,
--                 circle_id
--            FROM circle_block_grouped_ends
--           WHERE end_count = 2) c2
-- GROUP BY c2.circle_id
