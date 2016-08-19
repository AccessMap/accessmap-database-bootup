DROP TABLE IF EXISTS routing_nodes;
-- Create nodes table
CREATE TABLE routing_nodes AS SELECT id,
                                     ST_Centroid(ST_Collect(pt)) AS geom
                                FROM (      (SELECT source AS id,
                                                   ST_StartPoint(geom) AS pt
                                              FROM build.routing)
                                      UNION (SELECT target AS id,
                                                   ST_EndPoint(geom) AS pt
                                              FROM build.routing)) AS foo
                            GROUP BY id;
