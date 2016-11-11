DROP TABLE IF EXISTS public.sidewalks;
DROP TABLE IF EXISTS public.crossings;
DROP TABLE IF EXISTS public.curbramps;
DROP TABLE IF EXISTS public.sidewalks_orig;
DROP TABLE IF EXISTS public.curbramps_orig;

-- Copy to public schema and convert to latlon
-- sidewalks
CREATE TABLE public.sidewalks (like data.sidewalks INCLUDING INDEXES);
INSERT INTO public.sidewalks
     SELECT *
       FROM data.sidewalks;

ALTER TABLE public.sidewalks
ALTER COLUMN geom
        TYPE geometry(LINESTRING, 4326)
       USING ST_Transform(geom, 4326);

-- crossings
CREATE TABLE public.crossings (like build.crossings INCLUDING INDEXES);
INSERT INTO public.crossings
     SELECT *
       FROM build.crossings
   ORDER BY id;

ALTER TABLE public.crossings
ALTER COLUMN geom
        TYPE geometry(LINESTRING, 4326)
       USING ST_Transform(geom, 4326);

-- curbramps
CREATE TABLE public.curbramps (like data.curbramps INCLUDING INDEXES);
INSERT INTO public.curbramps
     SELECT *
       FROM data.curbramps;

ALTER TABLE public.curbramps
ALTER COLUMN geom
        TYPE geometry(POINT, 4326)
       USING ST_Transform(geom, 4326);
