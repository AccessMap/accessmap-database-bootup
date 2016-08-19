-- DROP TABLE IF EXISTS public.sidewalks;
-- DROP TABLE IF EXISTS public.crossings;
-- DROP TABLE IF EXISTS public.curbramps;
DROP TABLE IF EXISTS public.routing;
DROP TABLE IF EXISTS public.routing_vertices_pgr;

/* Copy (some) build tables to public */
-- CREATE TABLE public.sidewalks (like build.clean_sidewalks INCLUDING INDEXES);
-- INSERT INTO public.sidewalks
--      SELECT *
--        FROM build.clean_sidewalks;
--
-- CREATE TABLE public.crossings (like build.crossings INCLUDING INDEXES);
-- INSERT INTO public.crossings
--      SELECT *
--        FROM build.crossings;
--
-- CREATE TABLE public.crossings (like build.curbramps INCLUDING INDEXES);
-- INSERT INTO public.crossings
--      SELECT *
--        FROM build.curbramps;

CREATE TABLE public.routing (like build.routing INCLUDING INDEXES);
INSERT INTO public.routing
     SELECT *
       FROM build.routing;

CREATE TABLE public.routing_vertices_pgr (like build.routing_vertices_pgr INCLUDING INDEXES);
INSERT INTO public.routing_vertices_pgr
     SELECT *
       FROM build.routing_vertices_pgr;
