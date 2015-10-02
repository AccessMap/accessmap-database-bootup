-- Step0: IHow to change srid
--UPDATE table_name
--SET geom = ST_Transform(geom, 2926);
UPDATE curbramps
SET geom = ST_Transform(geom, 2926);

-- Step1: Pick the column that is useful
CREATE TABLE processed_sidewalks AS
SELECT id, ST_LineMerge(ST_Transform(geom,2926)) AS geom, segkey, curbramphighyn, curbramplowyn, curbrampmidyn from raw_sidewalks;
------ To check the output table, try this
SELECT * FROM processed_sidewalks limit 5;
------ Create spatial index and primary key
CREATE INDEX spatial_sidewalks ON processed_sidewalks USING gist(geom);
ALTER TABLE processed_sidewalks ADD PRIMARY KEY (id);

UPDATE processed_sidewalks 
SET s_geom = null
WHERE GeometryType(geom) != 'LINESTRING';

------ Comments on ST_LineMerge: There are 14 sidewalks have include more than 1 geometries. All of them can be merged using ST_LineMerge.

-- Step2: Assign curb ramps to nodes
------ Create new columns in table processed_sidewalks (default value is null)
ALTER TABLE processed_sidewalks 
ADD COLUMN id_curb_ramps_at_first_point int,
ADD COLUMN id_curb_ramps_at_last_point int;

------ For the first node in each geometry, find its closet curb ramps
UPDATE processed_sidewalks
SET id_curb_ramps_at_first_point = query.curb_id
FROM (
SELECT DISTINCT ON (s.id) s.id as sidewalk_id, c.id as curb_id
FROM processed_sidewalks as s
INNER JOIN curbramps as c ON ST_DWithin(ST_StartPoint(s.geom), c.geom, 1)
ORDER BY s.id, ST_Distance(ST_StartPoint(s.geom), c.geom)  ) AS query
WHERE query.sidewalk_id = processed_sidewalks.id;

----- Same for the last node in each geometry
UPDATE processed_sidewalks
SET id_curb_ramps_at_last_point = query.curb_id
FROM (
SELECT DISTINCT ON (s.id) s.id as sidewalk_id, c.id as curb_id
FROM processed_sidewalks as s
INNER JOIN curbramps as c ON ST_DWithin(ST_EndPoint(s.geom), c.geom, 1)
ORDER BY s.id, ST_Distance(ST_EndPoint(s.geom), c.geom)  ) AS query
WHERE query.sidewalk_id = processed_sidewalks.id

-- Step 3: Check the validity of the algorithm

--- Check from qgis
CREATE VIEW test_first_node AS 
SELECT DISTINCT ON (s.id) s.id as sidewalk_id, c.id as curb_id, ST_MakeLine(ST_EndPoint(s.geom), c.geom)
FROM processed_sidewalks as s
INNER JOIN curbramps as c ON ST_DWithin(ST_StartPoint(s.geom), c.geom, 0.01)
ORDER BY s.id, ST_Distance(ST_StartPoint(s.geom), c.geom)

CREATE VIEW test_seond_node AS 
SELECT DISTINCT ON (s.id) s.id as sidewalk_id, c.id as curb_id, ST_MakeLine(ST_StartPoint(s.geom), c.geom)
FROM processed_sidewalks as s
INNER JOIN curbramps as c ON ST_DWithin(ST_EndPoint(s.geom), c.geom, 0.01)
ORDER BY s.id, ST_Distance(ST_EndPoint(s.geom), c.geom)

--- Check from sidewalk curb ramp high street/ Low street indicators
-- 14113 have curbs at high and low, 975 sidewalks have two indicators, but we do not catch it in the dataset.
CREATE VIEW test AS 
SELECT id, geom from processed_sidewalks
WHERE (curbramphighyn = 'Y' AND curbramphighyn = 'Y') AND (id_curb_ramps_at_first_point is null AND id_curb_ramps_at_last_point is null)

ALTER TABLE connection ADD COLUMN mrdcrosswalk_id int;
UPDATE connection 
SET mrdcrosswalk_id = m.crosswalk_id
FROM (
SELECT DISTINCT ON (m.id) c.id as connection_id, m.id as crosswalk_id
FROM connection as c
LEFT JOIN mrkdcrosswalks as m ON ST_DWithin(ST_Transform(c.geom,4326), ST_Transform(m.geom, 4326),0.0001)
ORDER BY m.id, ST_Distance(ST_Transform(c.geom,4326), ST_Transform(m.geom, 4326))) AS m
WHERE id = m.connection_id;

