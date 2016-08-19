DROP TABLE IF EXISTS public.routing;

CREATE TABLE public.routing AS
      SELECT row_number() over() AS id,
                                    q.*
        FROM (   SELECT id AS o_id,
                              geom,
                              grade,
                              0 AS isCrossing
                   FROM public.sidewalks
              UNION ALL
                 SELECT id AS o_id,
                              geom,
                              grade,
                              1 AS isCrossing
                   FROM public.crossings) AS q
       WHERE GeometryType(q.geom) = 'LINESTRING';

CREATE INDEX routing_index
          ON public.routing
       USING gist(geom);

ALTER TABLE public.routing
 ADD COLUMN source integer;

ALTER TABLE public.routing
 ADD COLUMN target integer;

ALTER TABLE public.routing
 ADD COLUMN length float;

UPDATE public.routing
   SET length = ST_Length(geom::geography);

-- For some reason, the id column is bigint, should be integer for use in
-- pgrouting
 ALTER TABLE public.routing
ALTER COLUMN id
        TYPE integer
       USING id::integer;

SELECT pgr_createTopology('public.routing', 0.00001, 'geom', 'id');
