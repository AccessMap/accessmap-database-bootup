/*
Goal: Assign curbramps to sidewalks so that when sidewalk ends move, the
curbramp locations are also updated. In the end, curbramps become a property
of crossings that connect to the ends of sidewalks.

Strategy: data.curbramps contains curb ramps locations and data.sidewalks
contains sidewalks. Whenever the end of a sidewalk is in the same location as
a curb ramp (within some tolerance), it will be assigned to the 'start' or
'end' of the sidewalk
*/

ALTER TABLE data.sidewalks
 ADD COLUMN curbramp_start boolean
 ADD COLUMN curbramp_end boolean;


UPDATE TABLE data.sidewalks
         SET curbramp_start = EXISTS (SELECT DWithin(ST_StartPoint(sw.geom), c.geom, 0.001)
                                        FROM data.sidewalks AS sw
                                        JOIN data.curbramps AS c)
         SET curbramp_end = EXISTS (SELECT DWithin(ST_EndPoint(sw.geom), c.geom, 0.001)
                                        FROM data.sidewalks AS sw
                                        JOIN data.curbramps AS c)
