DROP TABLE IF EXISTS sidewalks_ready_routing;

CREATE TABLE sidewalks_ready_routing AS SELECT row_number() over() AS id,
                                                                      q.*
                                          FROM (   SELECT id AS o_id,
                                                                geom,
                                                                0 AS isCrossing
                                                     FROM clean_sidewalks
                                                UNION ALL
                                                   SELECT id AS o_id,
                                                                geom,
                                                                1 as isCrossing
                                                     FROM crossings) AS q
                                         WHERE GeometryType(q.geom) = 'LINESTRING';

ALTER TABLE sidewalks_ready_routing ADD COLUMN source integer;
ALTER TABLE sidewalks_ready_routing ADD COLUMN target integer;
SELECT pgr_createTopology('sidewalks_ready_routing', 0.00001, 'geom', 'id')
