/*

Goal: Add 'curbramps' boolean to crossings

Strategy: Recreate 'curbramps' cleaned-up data table after moving sidewalks,
          then apply 'curbramps' label to crossings if both sides have one.

*/

CREATE TEMPORARY TABLE tempcrossable AS
            SELECT c.id
              FROM (SELECT id,
                           ST_StartPoint(geom) AS startpoint,
                           ST_EndPoint(geom) AS endpoint
                      FROM crossings) c
CROSS JOIN LATERAL (SELECT *
                      FROM curbramps
                    ORDER BY c.startpoint <-> geom
                     LIMIT 1) cr1
CROSS JOIN LATERAL (SELECT *
                      FROM curbramps
                    ORDER BY c.endpoint <-> geom
                     LIMIT 1) cr2
             WHERE ST_DWithin(c.startpoint::geography, cr1.geom::geography, 0.1)
               AND ST_DWithin(c.endpoint::geography, cr2.geom::geography, 0.1);

UPDATE crossings c
   SET curbramps = true
  FROM tempcrossable t
 WHERE c.id = t.id;
