DROP TABLE IF EXISTS public.sidewalks;
DROP TABLE IF EXISTS public.crossings;
DROP TABLE IF EXISTS public.curbramps;
DROP TABLE IF EXISTS public.sidewalks_orig;
DROP TABLE IF EXISTS public.curbramps_orig;

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

-- original data for sidewalks, curb ramps
CREATE TABLE public.sidewalks_orig (like data.sidewalks INCLUDING INDEXES);
INSERT INTO public.sidewalks_orig
     SELECT *
       FROM data.sidewalks;

UPDATE public.sidewalks_orig
   SET geom = ST_Transform(geom, 4326);

CREATE TABLE public.curbramps_orig (like data.curbramps INCLUDING INDEXES);
INSERT INTO public.curbramps_orig
     SELECT *
       FROM data.curbramps;

UPDATE public.curbramps_orig
   SET geom = ST_Transform(geom, 4326);
