/*
Assign sidewalk ends to their closest intersection that's within a given
tolerance.
*/

DROP TABLE IF EXISTS grouped_ends;

CREATE TABLE grouped_ends AS
      SELECT
        FROM (SELECT ST_StartPoint(geom) AS geom,
                     'start' AS endtype
                FROM data.sidewalks
               UNION
              SELECT ST_EndPoint(geom) AS geom,
                     'end' AS endtype
                FROM data.sidewalks) sw_ends
        JOIN build.intersections i
          ON ST_DWithin(
