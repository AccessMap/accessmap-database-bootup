\timing
-- Create cleaned-up data tables for displaying on maps
CREATE TEMPORARY TABLE sidewalks_4269 AS
          SELECT s.geom,
                 ST_StartPoint(s.geom) AS startpoint,
                 ST_EndPoint(s.geom) AS endpoint,
                 s.id
            FROM (SELECT geom,
                         id
                    FROM build.clean_sidewalks) AS s;
CREATE INDEX tmp_sidewalks_start_index
          ON sidewalks_4269
       USING gist(startpoint);
CREATE INDEX tmp_sidewalks_end_index
          ON sidewalks_4269
       USING gist(endpoint);

CREATE TEMPORARY TABLE crossings_4269 AS
          SELECT c.geom,
                 ST_StartPoint(c.geom) AS startpoint,
                 ST_EndPoint(c.geom) AS endpoint,
                 c.id,
                 c.curbramps
            FROM (SELECT geom,
                         id,
                         curbramps
                    FROM build.crossings) AS c;
CREATE INDEX tmp_crossings_start_index
          ON crossings_4269
       USING gist(startpoint);
CREATE INDEX tmp_crossings_end_index
          ON crossings_4269
       USING gist(endpoint);

DROP TABLE IF EXISTS public.sidewalks;

CREATE TABLE public.sidewalks AS
      SELECT spoint.geom,
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE (epoint.elevation - spoint.elevation) / ST_Length(spoint.geom) END) AS grade,
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
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE (epoint.elevation - spoint.elevation) / ST_Length(spoint.geom) END) AS grade,
             spoint.curbramps,
             epoint.elevation - spoint.elevation AS ele_change,
             spoint.elevation AS ele_start,
             epoint.elevation AS ele_end,
             spoint.id
        FROM (SELECT ST_Value(n.rast, c.startpoint) AS elevation,
                     c.geom AS geom,
                     c.id,
                     c.curbramps
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
            FROM (SELECT geom,
                         id
                    FROM data.sidewalks) AS s;

DROP TABLE IF EXISTS public.sidewalks;

CREATE TABLE public.sidewalks AS
      SELECT spoint.geom,
             (CASE ST_Length(spoint.geom) WHEN 0 THEN 0 ELSE (epoint.elevation - spoint.elevation) / ST_Length(spoint.geom) END) AS grade,
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

DROP TABLE IF EXISTS public.curbramps;

CREATE TABLE public.curbramps AS
      SELECT id,
             geom
        FROM data.curbramps;
