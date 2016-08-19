DROP TABLE IF EXISTS public.sidewalks;
DROP TABLE IF EXISTS public.crossings;
DROP TABLE IF EXISTS public.curbramps;

-- Copy to public schema and convert to latlon
-- sidewalks
CREATE TABLE public.sidewalks (like build.clean_sidewalks INCLUDING INDEXES);
INSERT INTO public.sidewalks
     SELECT *
       FROM build.clean_sidewalks;

UPDATE public.sidewalks
   SET geom = ST_Transform(geom, 4326);

-- crossings
CREATE TABLE public.crossings (like build.crossings INCLUDING INDEXES);
INSERT INTO public.crossings
     SELECT *
       FROM build.crossings
   ORDER BY id;

UPDATE public.crossings
   SET geom = ST_Transform(geom, 4326);

-- curbramps
CREATE TABLE public.curbramps (like build.curbramps INCLUDING INDEXES);
INSERT INTO public.curbramps
     SELECT *
       FROM build.curbramps;

UPDATE public.curbramps
   SET geom = ST_Transform(geom, 4326);
