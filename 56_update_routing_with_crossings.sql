\timing


-- Create 'curbramps' column in routing table
ALTER TABLE routing DROP COLUMN IF EXISTS curbramps;
ALTER TABLE routing
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
