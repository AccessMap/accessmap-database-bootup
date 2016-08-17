DROP TABLE IF EXISTS build.routing;

CREATE TABLE build.routing AS
      SELECT row_number() over() AS id,
                                    q.*
        FROM (   SELECT id AS o_id,
                              geom,
                              0 AS isCrossing
                   FROM build.clean_sidewalks
              UNION ALL
                 SELECT id AS o_id,
                              geom,
                              1 AS isCrossing
                   FROM build.crossings) AS q
       WHERE GeometryType(q.geom) = 'LINESTRING';

ALTER TABLE build.routing
 ADD COLUMN source integer;

ALTER TABLE build.routing
 ADD COLUMN target integer;

SELECT pgr_createTopology('build.routing', 0.00001, 'geom', 'id');
