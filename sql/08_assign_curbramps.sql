/*
Goal: Assign curbramps to sidewalks so that when sidewalk ends move, the
curbramp locations are also updated. In the end, curbramps become a property
of crossings that connect to the ends of sidewalks.
Strategy: data.curbramps contains curb ramps locations and data.sidewalks
contains sidewalks. Whenever the end of a sidewalk is in the same location as
a curb ramp (within some tolerance), it will be assigned to the 'start' or
'end' of the sidewalk
*/
ALTER TABLE data.sidewalks DROP COLUMN IF EXISTS curbramp_start;
ALTER TABLE data.sidewalks DROP COLUMN IF EXISTS curbramp_end;

ALTER TABLE data.sidewalks ADD COLUMN curbramp_start boolean DEFAULT 'f';
ALTER TABLE data.sidewalks ADD COLUMN curbramp_end boolean DEFAULT 'f';

UPDATE data.sidewalks sw
   SET curbramp_start = 't'
  FROM data.curbramps c
 WHERE ST_DWithin(ST_StartPoint(sw.geom), c.geom, 0.001);

UPDATE data.sidewalks sw
   SET curbramp_end = 't'
  FROM data.curbramps c
 WHERE ST_DWithin(ST_EndPoint(sw.geom), c.geom, 0.001);
