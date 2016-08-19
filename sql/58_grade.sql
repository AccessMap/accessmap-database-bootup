ALTER TABLE build.routing DROP COLUMN IF EXISTS grade;
ALTER TABLE build.routing ADD COLUMN grade float;

/*
UPDATE routing r
   SET grade = s.grade
  FROM sidewalks s
 WHERE r.iscrossing = 0
   AND r.o_id = s.id;

UPDATE routing r
   SET grade = c.grade
  FROM crossings c
 WHERE r.iscrossing = 1
   AND r.o_id = c.id;
*/

UPDATE build.routing r
   SET grade = CASE WHEN ST_Length(r.geom) = 0 THEN 0 ELSE ele_change / ST_Length(r.geom) END;
