/*

Goal: Add 'curbramps' boolean to crossings

Strategy: Recreate 'curbramps' cleaned-up data table after moving sidewalks,
          then apply 'curbramps' label to crossings if both sides have one.

*/
ALTER TABLE build.crossings
 ADD COLUMN curbramps boolean;

CREATE TEMPORARY TABLE tempcrossable AS
            SELECT c.id
              FROM (SELECT id,
                           ST_StartPoint(geom) AS startpoint,
                           ST_EndPoint(geom) AS endpoint
                      FROM build.crossings) c
CROSS JOIN LATERAL (SELECT *
                      FROM data.curbramps
                    ORDER BY c.startpoint <-> geom
                     LIMIT 1) cr1
CROSS JOIN LATERAL (SELECT *
                      FROM data.curbramps
                    ORDER BY c.endpoint <-> geom
                     LIMIT 1) cr2
             WHERE ST_DWithin(c.startpoint, cr1.geom, 0.1)
               AND ST_DWithin(c.endpoint, cr2.geom, 0.1);

UPDATE build.crossings c
   SET curbramps = true
  FROM tempcrossable t
 WHERE c.id = t.id;
