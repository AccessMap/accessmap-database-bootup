\timing
-- Create cleaned-up data tables for displaying on maps
CREATE TEMPORARY TABLE sidewalks_4269 AS
          SELECT s.geom,
                 ST_StartPoint(s.geom) AS startpoint,
                 ST_EndPoint(s.geom) AS endpoint,
                 s.id
            FROM (SELECT ST_Transform(geom, 4269) AS geom,
                         id
                    FROM build.clean_sidewalks) AS s;

CREATE TEMPORARY TABLE crossings_4269 AS
          SELECT c.geom,
                 ST_StartPoint(c.geom) AS startpoint,
                 ST_EndPoint(c.geom) AS endpoint,
                 c.id
            FROM (SELECT ST_Transform(geom, 4269) AS geom,
                         id
                    FROM build.crossings) AS c;

DROP TABLE IF EXISTS public.sidewalks;

CREATE TABLE public.sidewalks AS
      SELECT spoint.geom,
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE ABS(epoint.elevation - spoint.elevation) / ST_Length(spoint.geom::geography) END) AS grade,
             epoint.elevation - spoint.elevation AS ele_change,
             spoint.elevation AS ele_start,
             epoint.elevation AS ele_end,
             spoint.id
        FROM (SELECT ST_Value(n.rast, s.startpoint) AS elevation,
                     s.geom,
                     s.id
                FROM sidewalks_4269 AS s,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, s.startpoint)) AS spoint
                JOIN
             (SELECT ST_Value(n.rast, s.endpoint) AS elevation,
                     s.id
                FROM sidewalks_4269 AS s,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, s.endpoint)) AS epoint
                  ON spoint.id = epoint.id
    ORDER BY spoint.id;

DROP TABLE IF EXISTS public.crossings;

CREATE TABLE public.crossings AS
      SELECT spoint.geom,
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE ABS(epoint.elevation - spoint.elevation) / ST_Length(spoint.geom::geography) END) AS grade,
             epoint.elevation - spoint.elevation AS ele_change,
             spoint.elevation AS ele_start,
             epoint.elevation AS ele_end,
             spoint.id
        FROM (SELECT ST_Value(n.rast, c.startpoint) AS elevation,
                     c.geom,
                     c.id
                FROM crossings_4269 AS c,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, c.startpoint)) AS spoint
                JOIN
             (SELECT ST_Value(n.rast, c.endpoint) AS elevation,
                     c.id
                FROM crossings_4269 AS c,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, c.endpoint)) AS epoint
                  ON spoint.id = epoint.id
    ORDER BY spoint.id;


-- Create source (pre-cleaning) data tables for displaying on maps
CREATE TEMPORARY TABLE sidewalks_data_4269 AS
          SELECT s.geom,
                 ST_StartPoint(s.geom) AS startpoint,
                 ST_EndPoint(s.geom) AS endpoint,
                 s.id
            FROM (SELECT ST_Transform(geom, 4269) AS geom,
                         id
                    FROM data.sidewalks) AS s;

DROP TABLE IF EXISTS public.sidewalks_data;

CREATE TABLE public.sidewalks_data AS
      SELECT spoint.geom,
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE ABS(epoint.elevation - spoint.elevation) / ST_Length(spoint.geom::geography) END) AS grade,
             epoint.elevation - spoint.elevation AS ele_change,
             spoint.elevation AS ele_start,
             epoint.elevation AS ele_end,
             spoint.id
        FROM (SELECT ST_Value(n.rast, s.startpoint) AS elevation,
                     s.geom,
                     s.id
                FROM sidewalks_data_4269 AS s,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, s.startpoint)) AS spoint
                JOIN
             (SELECT ST_Value(n.rast, s.endpoint) AS elevation,
                     s.id
                FROM sidewalks_data_4269 AS s,
                     data.ned13 AS n
               WHERE ST_Intersects(n.rast, s.endpoint)) AS epoint
                  ON spoint.id = epoint.id
    ORDER BY spoint.id;

DROP TABLE IF EXISTS public.curbramps_data;

CREATE TABLE public.curbramps_data AS
      SELECT id,
             geom
        FROM data.curbramps;
