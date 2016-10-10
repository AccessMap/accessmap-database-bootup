/*
Some sidewalks are drawn directly on top of streets - this is bad.

There are probably better strategies, but this one should work:
(1) Find the distance from each sidewalk point to the closest street
(2) If the distance from *all* the points to each nearest street is less than
a small threshold (e.g. 0.1 meters), remove the sidewalk.
*/

-- First, get all sidewalks that are close to streets at all.
CREATE TEMPORARY TABLE close_sidewalks AS
SELECT DISTINCT ON (sw.id) sw.geom AS sw_geom,
                           st.geom AS st_geom,
                           sw.id AS sw_id,
                           st.id AS st_id
                      FROM data.streets st
                      JOIN data.sidewalks sw
                        ON ST_DWithin(st.geom, sw.geom, 0.1)
                  ORDER BY sw.id, st.geom <-> sw.geom;

-- Now check all of their points
DELETE FROM data.sidewalks
      USING (   SELECT every(close) AS disqualified,
                      sw_id
                 FROM (SELECT *,
                              ST_Distance((ST_DumpPoints(sw_geom)).geom, st_geom) < 0.1 AS close
                         FROM close_sidewalks) dumped
             GROUP BY dumped.sw_id) a
      WHERE a.disqualified
        AND a.sw_id = id;
