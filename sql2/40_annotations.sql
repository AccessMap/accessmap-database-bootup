\timing
ALTER TABLE build.clean_sidewalks
 ADD COLUMN grade NUMERIC(6, 4);

ALTER TABLE build.clean_sidewalks
 ADD COLUMN ele_start NUMERIC(10, 1);

ALTER TABLE build.clean_sidewalks
 ADD COLUMN ele_end NUMERIC(10, 1);

ALTER TABLE build.crossings
 ADD COLUMN grade NUMERIC(6, 4);

ALTER TABLE build.crossings
 ADD COLUMN ele_start NUMERIC(10, 1);

ALTER TABLE build.crossings
 ADD COLUMN ele_end NUMERIC(10, 1);

ALTER TABLE data.sidewalks
 ADD COLUMN grade NUMERIC(6, 4);

ALTER TABLE data.sidewalks
 ADD COLUMN ele_start NUMERIC(10, 1);

ALTER TABLE data.sidewalks
 ADD COLUMN ele_end NUMERIC(10, 1);

-- Remove length-0 edges
DELETE FROM build.clean_sidewalks
      WHERE ST_Length(geom) = 0;

DELETE FROM build.crossings
      WHERE ST_Length(geom) = 0;

DELETE FROM data.sidewalks
      WHERE ST_Length(geom) = 0;

-- Due to problems in reprojecting the raster table itself, we need to
-- reproject the start/endpoint geometries of sidewalks and crossings, create
-- spatial indices on these, and then look up the raster data

CREATE TEMPORARY TABLE sidewalk_endpoints AS
                SELECT s.id,
                       ST_Transform(ST_StartPoint(s.geom), n.srid) AS startpoint,
                       ST_Transform(ST_EndPoint(s.geom), n.srid) AS endpoint
                  FROM build.clean_sidewalks s,
                       (SELECT ST_SRID(rast) AS srid
                          FROM data.ned13
                         LIMIT 1) n;

CREATE TEMPORARY TABLE crossing_endpoints AS
                SELECT c.id,
                       ST_Transform(ST_StartPoint(c.geom), n.srid) AS startpoint,
                       ST_Transform(ST_EndPoint(c.geom), n.srid) AS endpoint
                  FROM build.crossings c,
                       (SELECT ST_SRID(rast) AS srid
                          FROM data.ned13
                         LIMIT 1) n;

CREATE TEMPORARY TABLE sidewalk_data_endpoints AS
                SELECT s.id,
                       ST_Transform(ST_StartPoint(s.geom), n.srid) AS startpoint,
                       ST_Transform(ST_EndPoint(s.geom), n.srid) AS endpoint
                  FROM data.sidewalks s,
                       (SELECT ST_SRID(rast) AS srid
                          FROM data.ned13
                         LIMIT 1) n;

UPDATE build.clean_sidewalks s
   SET ele_start = ST_Value(n.rast,  e.startpoint)
  FROM data.ned13 n,
       sidewalk_endpoints e
 WHERE ST_Intersects(n.rast, e.startpoint)
   AND s.id = e.id;

UPDATE build.clean_sidewalks s
   SET ele_end = ST_Value(n.rast,  e.endpoint)
  FROM data.ned13 n,
       sidewalk_endpoints e
 WHERE ST_Intersects(n.rast, e.endpoint)
   AND s.id = e.id;

UPDATE build.crossings s
   SET ele_start = ST_Value(n.rast,  e.startpoint)
  FROM data.ned13 n,
       crossing_endpoints e
 WHERE ST_Intersects(n.rast, e.startpoint)
   AND s.id = e.id;

UPDATE build.crossings s
   SET ele_end = ST_Value(n.rast,  e.endpoint)
  FROM data.ned13 n,
       crossing_endpoints e
 WHERE ST_Intersects(n.rast, e.endpoint)
   AND s.id = e.id;

UPDATE data.sidewalks s
   SET ele_start = ST_Value(n.rast,  e.startpoint)
  FROM data.ned13 n,
       sidewalk_data_endpoints e
 WHERE ST_Intersects(n.rast, e.startpoint)
   AND s.id = e.id;

UPDATE data.sidewalks s
   SET ele_end = ST_Value(n.rast,  e.endpoint)
  FROM data.ned13 n,
       sidewalk_data_endpoints e
 WHERE ST_Intersects(n.rast, e.endpoint)
   AND s.id = e.id;

UPDATE build.clean_sidewalks
   SET grade = (ele_end - ele_start) / ST_Length(geom);

UPDATE build.crossings
   SET grade = (ele_end - ele_start) / ST_Length(geom);

UPDATE data.sidewalks
   SET grade = (ele_end - ele_start) / ST_Length(geom);
