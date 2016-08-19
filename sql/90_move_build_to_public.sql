/*
DROP TABLE IF EXISTS sidewalks;
DROP TABLE IF EXISTS crossings;
*/
DROP TABLE IF EXISTS routing;
DROP TABLE IF EXISTS routing_vertices_pgr;

/* Copy (some) build tables to public */
/*
CREATE TABLE sidewalks (like build.clean_sidewalks INCLUDING INDEXES);
INSERT INTO sidewalks
     SELECT *
       FROM build.clean_sidewalks;

CREATE TABLE crossings (like build.crossings INCLUDING INDEXES);
INSERT INTO crossings
     SELECT *
       FROM build.crossings;
*/
CREATE TABLE public.routing (like build.routing INCLUDING INDEXES);
INSERT INTO public.routing
     SELECT *
       FROM build.routing;

CREATE TABLE public.routing_vertices_pgr (like build.routing_vertices_pgr INCLUDING INDEXES);
INSERT INTO public.routing_vertices_pgr
     SELECT *
       FROM build.routing_vertices_pgr;
