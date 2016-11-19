\timing
ALTER TABLE sidewalks
 ADD COLUMN grade NUMERIC(6, 4);

ALTER TABLE sidewalks
 ADD COLUMN ele_start NUMERIC(10, 1);

ALTER TABLE sidewalks
 ADD COLUMN ele_end NUMERIC(10, 1);

ALTER TABLE crossings
 ADD COLUMN grade NUMERIC(6, 4);

ALTER TABLE crossings
 ADD COLUMN ele_start NUMERIC(10, 1);

ALTER TABLE crossings
 ADD COLUMN ele_end NUMERIC(10, 1);

-- Remove length-0 edges
DELETE FROM sidewalks
      WHERE ST_Length(geom) = 0;

DELETE FROM crossings
      WHERE ST_Length(geom) = 0;

-- Due to problems in reprojecting the raster table itself, we need to
-- reproject the start/endpoint geometries of sidewalks and crossings, create
-- spatial indices on these, and then look up the raster data

CREATE TEMPORARY TABLE sidewalk_endpoints AS
                SELECT s.gid AS id,
                       ST_Transform(ST_StartPoint(s.geom), n.srid) AS startpoint,
                       ST_Transform(ST_EndPoint(s.geom), n.srid) AS endpoint
                  FROM sidewalks s,
                       (SELECT ST_SRID(rast) AS srid
                          FROM dem.n48w123
                         LIMIT 1) n;

CREATE TEMPORARY TABLE crossing_endpoints AS
                SELECT c.id,
                       ST_Transform(ST_StartPoint(c.geom), n.srid) AS startpoint,
                       ST_Transform(ST_EndPoint(c.geom), n.srid) AS endpoint
                  FROM crossings c,
                       (SELECT ST_SRID(rast) AS srid
                          FROM dem.n48w123
                         LIMIT 1) n;

UPDATE sidewalks s
   SET ele_start = ST_Value(n.rast,  e.startpoint)
  FROM dem.n48w123 n,
       sidewalk_endpoints e
 WHERE ST_Intersects(n.rast, e.startpoint)
   AND s.gid = e.id;

UPDATE sidewalks s
   SET ele_end = ST_Value(n.rast,  e.endpoint)
  FROM dem.n48w123 n,
       sidewalk_endpoints e
 WHERE ST_Intersects(n.rast, e.endpoint)
   AND s.gid = e.id;

UPDATE crossings s
   SET ele_start = ST_Value(n.rast,  e.startpoint)
  FROM dem.n48w123 n,
       crossing_endpoints e
 WHERE ST_Intersects(n.rast, e.startpoint)
   AND s.id = e.id;

UPDATE crossings s
   SET ele_end = ST_Value(n.rast,  e.endpoint)
  FROM dem.n48w123 n,
       crossing_endpoints e
 WHERE ST_Intersects(n.rast, e.endpoint)
   AND s.id = e.id;

UPDATE sidewalks
   SET grade = (ele_end - ele_start) / ST_Length(geom);

UPDATE crossings
   SET grade = (ele_end - ele_start) / ST_Length(geom);
