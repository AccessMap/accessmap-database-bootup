-- Drop tables created in this step prior to recreating them
DROP TABLE IF EXISTS build.intersections;

---------------------------------------
-- Create intersections from streets --
---------------------------------------
-- Find intersection point from street
-- Note: For each intersection, the street id, points and degree is sorted in clock-wise order.
CREATE TABLE build.intersections AS
      SELECT row_number() over() AS id,
		     geom,
		     array_agg(s_id) AS s_id,
		     array_agg(other) AS s_others,
		     array_agg(degree) AS degree,
		     count(id) AS num_s
	    FROM (SELECT *,
	                 row_number() over() AS id
	            FROM (SELECT ST_PointN(p.geom, 1) AS geom,
	                         id AS s_id,
	                         ST_PointN(p.geom, 2) AS other,
	                         ST_Azimuth(ST_PointN(p.geom, 1), ST_PointN(p.geom, 2)) AS degree
	                    FROM data.streets AS p
                       UNION
                      SELECT ST_PointN(p.geom,ST_NPoints(p.geom)) AS geom,
	                         id AS s_id,
	                         ST_PointN(p.geom,ST_NPoints(p.geom) - 1) AS other,
	                         ST_Azimuth(ST_PointN(p.geom, ST_NPoints(p.geom)), ST_PointN(p.geom,ST_NPoints(p.geom) - 1)) AS degree
	                    FROM data.streets AS p) AS q
	         ORDER BY geom, st_azimuth(q.geom, q.other)) AS q2
	GROUP BY geom;

CREATE INDEX intersections_index
          ON build.intersections
       USING gist(geom);

ALTER TABLE build.intersections
        ADD PRIMARY KEY (id);
