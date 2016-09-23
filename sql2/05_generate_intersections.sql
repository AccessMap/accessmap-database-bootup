-- Drop tables created in this step prior to recreating them
DROP TABLE IF EXISTS build.intersections;

---------------------------------------
-- Create intersections from streets --
---------------------------------------
-- Find intersection point from street
-- Note: For each intersection, the street id, points and azimuth is sorted in clock-wise order.
-- FIXME: Using the azimuths out of intersections is not perfect, because many
-- of the street geometries are weird near the intersection, pointing at funny
-- angles (e.g data.street with id 25741 near 41st & 15th). Should use a new
-- strategy to decide whether sidewalk ends should be considered 'grouped',
-- i.e. potentially merged.
CREATE TABLE build.intersections AS
      SELECT row_number() over() AS id,
		     geom,
		     array_agg(s_id) AS s_id,
		     array_agg(next) AS s_nexts,
		     count(id) AS num_s
	    FROM (SELECT *,
                row_number() over() AS id
	            FROM (SELECT starts.start_point AS geom,
	                         id AS s_id,
                             starts.next_point AS next
	                    FROM (SELECT ST_StartPoint(geom) AS start_point,
                                     ST_PointN(geom, 2) AS next_point,
                                     id
                                FROM data.streets) AS starts
                       UNION
                      SELECT ends.start_point AS geom,
	                         id AS s_id,
	                         ends.next_point AS next
	                    FROM (SELECT ST_EndPoint(geom) AS start_point,
                                     ST_PointN(geom, ST_NPoints(geom) - 1) AS next_point,
                                     id
                                FROM data.streets) AS ends) AS endpoints
	         ORDER BY geom, ST_Azimuth(endpoints.geom, endpoints.next)) AS q2
	GROUP BY geom;

CREATE INDEX intersections_index
          ON build.intersections
       USING gist(geom);

ALTER TABLE build.intersections
        ADD PRIMARY KEY (id);
