DROP TABLE IF EXISTS sidewalks;
DROP TABLE IF EXISTS crossings;
DROP TABLE IF EXISTS routing;
DROP TABLE IF EXISTS routing_vertices_pgr;

ALTER TABLE build.clean_sidewalks SET SCHEMA public;
ALTER TABLE build.crossings SET SCHEMA public;
ALTER TABLE build.routing SET SCHEMA public;
ALTER TABLE build.routing_vertices_pgr SET SCHEMA public;

ALTER TABLE clean_sidewalks RENAME TO sidewalks;
