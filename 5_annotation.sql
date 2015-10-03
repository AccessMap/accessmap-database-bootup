-- Step 0: Change srid
-- FIXME: Fix CRS settings earlier than this
UPDATE curbramps
   SET geom = ST_Transform(geom, 2926);

-- Step1: Pick the column that is useful
-- FIXME: v_sidewalks shouldn't be touched at this point - we should use a different strategy for curb ramps
DROP TABLE IF EXISTS annotated_sidewalks;
CREATE TABLE annotated_sidewalks AS SELECT compkey as id,
                                           ST_LineMerge(ST_Transform(wkb_geometry, 2926)) AS geom,
                                           segkey,
                                           curbramphighyn,
                                           curbramplowyn,
                                           curbrampmidyn
                                      FROM v_sidewalks;

------ Create spatial index and primary key
CREATE INDEX annotated_sidewalks_index
          ON annotated_sidewalks
       USING gist(geom);

ALTER TABLE annotated_sidewalks
        ADD PRIMARY KEY (id);

UPDATE annotated_sidewalks
   SET geom = null
 WHERE GeometryType(geom) != 'LINESTRING';

------ Comments on ST_LineMerge: There are 14 sidewalks have include more than 1 geometries. All of them can be merged using ST_LineMerge.

-- Step2: Assign curb ramps to nodes
------ Create new columns in table sidewalks (default value is null)
ALTER TABLE annotated_sidewalks
 ADD COLUMN id_curb_ramps_at_first_point int,
 ADD COLUMN id_curb_ramps_at_last_point int;

------ For the first node in each geometry, find its closet curb ramps
UPDATE annotated_sidewalks
   SET id_curb_ramps_at_first_point = query.curb_id
  FROM (SELECT DISTINCT ON (s.id) s.id AS sidewalk_id,
                                  c.id AS curb_id
                      FROM annotated_sidewalks AS s
                INNER JOIN curbramps AS c
                        ON ST_DWithin(ST_StartPoint(s.geom), c.geom, 1)
                  ORDER BY s.id, ST_Distance(ST_StartPoint(s.geom), c.geom)) AS query
 WHERE query.sidewalk_id = annotated_sidewalks.id;

----- Same for the last node in each geometry
UPDATE annotated_sidewalks
   SET id_curb_ramps_at_last_point = query.curb_id
  FROM (SELECT DISTINCT ON (s.id) s.id AS sidewalk_id,
                                  c.id AS curb_id
                      FROM annotated_sidewalks AS s
                INNER JOIN curbramps AS c
                        ON ST_DWithin(ST_EndPoint(s.geom), c.geom, 1)
                  ORDER BY s.id,
                           ST_Distance(ST_EndPoint(s.geom), c.geom)) AS query
 WHERE query.sidewalk_id = annotated_sidewalks.id

-- Step 3: Check the validity of the algorithm

/*
--- Check from qgis
CREATE VIEW test_first_node AS SELECT DISTINCT ON (s.id) s.id AS sidewalk_id,
                                                         c.id AS curb_id,
                                                         ST_MakeLine(ST_EndPoint(s.geom), c.geom)
                                             FROM annotated_sidewalks AS s
                                       INNER JOIN curbramps AS c
                                               ON ST_DWithin(ST_StartPoint(s.geom), c.geom, 0.01)
                                         ORDER BY s.id,
                                                  ST_Distance(ST_StartPoint(s.geom), c.geom)

CREATE VIEW test_seond_node AS SELECT DISTINCT ON (s.id) s.id AS sidewalk_id,
                                                         c.id AS curb_id,
                                                         ST_MakeLine(ST_StartPoint(s.geom), c.geom)
                                             FROM annotated_sidewalks AS s
                                       INNER JOIN curbramps AS c
                                               ON ST_DWithin(ST_EndPoint(s.geom), c.geom, 0.01)
                                         ORDER BY s.id, ST_Distance(ST_EndPoint(s.geom), c.geom)

--- Check from sidewalk curb ramp high street/ Low street indicators
-- 14113 have curbs at high and low, 975 annotated_sidewalks have two indicators, but we do not catch it in the dataset.
CREATE VIEW test AS SELECT id,
                           geom
                      FROM annotated_sidewalks
                      WHERE (curbramphighyn = 'Y'
                             AND curbramphighyn = 'Y')
                             AND (id_curb_ramps_at_first_point IS NULL
                             AND id_curb_ramps_at_last_point IS NULL)

ALTER TABLE connection
 ADD COLUMN mrdcrosswalk_id int;

UPDATE connection
   SET mrdcrosswalk_id = m.crosswalk_id
  FROM (SELECT DISTINCT ON (m.id) c.id AS connection_id,
                                  m.id AS crosswalk_id
                      FROM connection AS c
                 LEFT JOIN mrkdcrosswalks AS m
                        ON ST_DWithin(ST_Transform(c.geom,4326), ST_Transform(m.geom, 4326),0.0001)
                  ORDER BY m.id, ST_Distance(ST_Transform(c.geom,4326), ST_Transform(m.geom, 4326))) AS m
 WHERE id = m.connection_id;
*/
