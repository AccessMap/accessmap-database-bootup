DROP TABLE IF EXISTS public.routing;

CREATE TABLE public.routing AS
      SELECT row_number() over()::integer AS id,
                                             q.*
        FROM (   SELECT gid AS o_id,
                               geom,
                               grade,
                               0 AS isCrossing,
                               ST_Length(geom::geography),
                               1 AS source,
                               1 AS target
                   FROM public.sidewalks
              UNION ALL
                 SELECT id AS o_id,
                              geom,
                              grade,
                              1 AS isCrossing,
                              ST_Length(geom::geography),
                              1 AS source,
                              1 AS target
                   FROM public.crossings) AS q
       WHERE GeometryType(q.geom) = 'LINESTRING';

CREATE INDEX routing_index
          ON public.routing
       USING gist(geom);

SELECT pgr_createTopology('public.routing', 0.00001, 'geom', 'id');
