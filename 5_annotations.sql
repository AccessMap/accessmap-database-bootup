\timing
ALTER TABLE sidewalks_ready_routing
 DROP COLUMN IF EXISTS ele_start,
 DROP COLUMN IF EXISTS ele_end,
 DROP COLUMN IF EXISTS ele_change,
 ADD COLUMN ele_start double precision,
 ADD COLUMN ele_end double precision,
 ADD COLUMN ele_change double precision;

UPDATE sidewalks_ready_routing
SET ele_start = sw.s_start
FROM (
    SELECT ST_Value(ned13.rast, ST_Transform(ST_StartPoint(geom), 4269)) AS s_start,
    id AS sid
    FROM sidewalks_ready_routing, ned13
    WHERE ST_Intersects(ned13.rast, ST_Transform(ST_StartPoint(geom), 4269))
     ) AS sw
WHERE id = sw.sid;

UPDATE sidewalks_ready_routing
SET ele_end = sw.s_end
FROM (
    SELECT ST_Value(ned13.rast, ST_Transform(ST_EndPoint(geom), 4269)) AS s_end,
    id AS sid
    FROM sidewalks_ready_routing, ned13
    WHERE ST_Intersects(ned13.rast, ST_Transform(ST_EndPoint(geom), 4269))
     ) AS sw
WHERE id = sw.sid;

UPDATE sidewalks_ready_routing
SET ele_change = sw.ele_start - sw.ele_end
FROM (
      SELECT ele_start, ele_end, id AS sid
      FROM sidewalks_ready_routing
      ) AS sw
WHERE id = sw.sid;
