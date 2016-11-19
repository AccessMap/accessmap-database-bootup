ALTER TABLE crossings
 DROP COLUMN IF EXISTS curbramps;

ALTER TABLE crossings
 ADD COLUMN curbramps boolean DEFAULT false;

/*
 * Label crossing as having curb ramps on both sides if *both* ends are within
 * a certain distance of any curb ramps
 */

-- TODO: get more accurate data, restrict distance to be lower than 8 meters
UPDATE crossings cr1
   SET curbramps=true
  FROM (SELECT DISTINCT havestart.id
          FROM (SELECT cr2.geom,
                       cr2.id
                  FROM crossings cr2
                  JOIN curbramps c1
                    ON ST_DWithin(ST_StartPoint(cr2.geom), c1.geom, 8)) havestart
          JOIN curbramps c2
            ON ST_DWithin(ST_EndPoint(havestart.geom), c2.geom, 8)) a
 WHERE cr1.id = a.id;
