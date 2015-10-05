DROP TABLE IF EXISTS sidewalks_ready_routing;

CREATE TABLE sidewalks_ready_routing AS SELECT row_number() over() AS id,
                                                                      q.*
                                          FROM (   SELECT id AS o_id,
                                                                geom,
                                                                0 AS isCrossing
                                                     FROM cleaned_sidewalks
                                                UNION ALL
                                                   SELECT id AS o_id,
                                                                geom,
                                                                1 as isCrossing
                                                     FROM connection) AS q
                                         WHERE GeometryType(q.geom) = 'LINESTRING';
