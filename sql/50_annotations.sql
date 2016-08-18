\timing
           ALTER TABLE build.routing
 DROP COLUMN IF EXISTS ele_start,
 DROP COLUMN IF EXISTS ele_end,
 DROP COLUMN IF EXISTS ele_change,
            ADD COLUMN ele_start double precision,
            ADD COLUMN ele_end double precision,
            ADD COLUMN ele_change double precision;

UPDATE build.routing r
   SET ele_start = ST_Value(n.rast, ST_StartPoint(r.geom))
  FROM data.ned13 n
 WHERE ST_Intersects(n.rast, ST_StartPoint(r.geom));

UPDATE build.routing r
   SET ele_end = ST_Value(n.rast, ST_EndPoint(r.geom))
  FROM data.ned13 n
 WHERE ST_Intersects(n.rast, ST_EndPoint(r.geom));


-- UPDATE build.routing
--    SET ele_start = point.elevation
--   FROM (SELECT ST_Value(n.rast, ST_StartPoint(r.geom)) AS elevation,
--                r.id AS id
--           FROM build.routing r,
--                data.ned13 n
--          WHERE ST_Intersects(n.rast, ST_StartPoint(r.geom))) point
--  WHERE id = point.id;
--
-- UPDATE build.routing
--    SET ele_end = point.elevation
--   FROM (SELECT ST_Value(n.rast, ST_EndPoint(r.geom)) AS elevation,
--                r.id AS id
--           FROM build.routing r,
--                data.ned13 n
--          WHERE ST_Intersects(n.rast, ST_EndPoint(r.geom))) point
--  WHERE id = point.id;

UPDATE build.routing r
   SET ele_change = sw.ele_start - sw.ele_end
  FROM (SELECT ele_start,
               ele_end,
               id AS sid
          FROM build.routing) AS sw
WHERE r.id = sw.sid;
