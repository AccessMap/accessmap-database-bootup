/*

Goal: Add 'curbramps' boolean to crossings

Strategy: Recreate 'curbramps' cleaned-up data table after moving sidewalks,
          then apply 'curbramps' label to crossings if both sides have one.

*/


-- Create the new curbramps table
DROP TABLE IF EXISTS public.curbramps;
CREATE TABLE public.curbramps AS SELECT cr.geom
                                   FROM (SELECT ST_StartPoint(sw.geom) AS geom
                                           FROM build.clean_sidewalks sw
                                          WHERE curbramp_start
                                          UNION
                                         SELECT ST_EndPoint(sw.geom) AS geom
                                           FROM build.clean_sidewalks sw
                                          WHERE curbramp_end) AS cr;
CREATE INDEX curbramps_index
          ON curbramps
       USING gist(geom);

-- Create 'curbramps' column in routing table
ALTER TABLE routing DROP COLUMN IF EXISTS curbramps;
ALTER TABLE routing
 ADD COLUMN curbramps boolean DEFAULT false;

ALTER TABLE crossings DROP COLUMN IF EXISTS curbramps;
ALTER TABLE crossings
 ADD COLUMN curbramps boolean DEFAULT false;

-- Update curbramps column
UPDATE routing r
   SET curbramps = true
  FROM (SELECT r1.id
          FROM (SELECT r.id
                  FROM routing r
                  JOIN public.curbramps cr
                    ON ST_DWithin(ST_StartPoint(r.geom), cr.geom, 0.1)) AS r1
          JOIN (SELECT r.id
                  FROM routing r
                  JOIN public.curbramps cr
                    ON ST_DWithin(ST_EndPoint(r.geom), cr.geom, 0.1)) AS r2
            ON r1.id = r2.id) r3
 WHERE r.id = r3.id
   AND iscrossing = 1;

UPDATE crossings r
   SET curbramps = true
  FROM (SELECT r1.id
          FROM (SELECT r.id
                  FROM routing r
                  JOIN public.curbramps cr
                    ON ST_DWithin(ST_StartPoint(r.geom), cr.geom, 0.1)) AS r1
          JOIN (SELECT r.id
                  FROM routing r
                  JOIN public.curbramps cr
                    ON ST_DWithin(ST_EndPoint(r.geom), cr.geom, 0.1)) AS r2
            ON r1.id = r2.id) r3
 WHERE r.id = r3.id;
