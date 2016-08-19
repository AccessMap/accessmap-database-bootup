ALTER TABLE build.routing
 ADD COLUMN cost double precision ;

UPDATE build.routing
   SET cost = 1 * ST_length(geom) + CASE ST_length(geom) WHEN 0 THEN 0 ELSE 1e10 * POW(ABS(ele_change) / ST_length(geom), 4) END;
