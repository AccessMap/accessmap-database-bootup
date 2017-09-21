DROP TABLE IF EXISTS routing;

CREATE TABLE routing AS
      SELECT row_number() over()::integer AS id,
                                             q.*
        FROM (   SELECT gid AS o_id,
                               geom,
                               grade,
                               FALSE AS iscrossing,
                               ST_Length(geom::geography) AS length,
                               FALSE AS curbramps,
                               1 AS source,
                               1 AS target
                   FROM sidewalks
              UNION ALL
                 SELECT gid AS o_id,
                              geom,
                              grade,
                              TRUE AS isCcossing,
                              ST_Length(geom::geography) AS length,
                              curbramps,
                              1 AS source,
                              1 AS target
                   FROM crossings) AS q
       WHERE GeometryType(q.geom) = 'LINESTRING';

CREATE INDEX routing_index
          ON routing
       USING gist(geom);

SELECT pgr_createTopology('routing', 1e-6, 'geom', clean:=true);

-- Create 'noded' version of network: all intersecting paths are now connected
-- Can make more sense for some analyses, given imperfect footpath data.

DROP TABLE IF EXISTS routing_noded;
SELECT pgr_nodeNetwork('routing', 1e-6, the_geom:='geom');
SELECT pgr_createTopology('routing_noded', 1e-6, 'geom', clean:=true);
