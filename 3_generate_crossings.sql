/*
input tables:
    clean_sidewalks
    intersections

output tables:
    corners
    intersection_group
    corner_group
    crossings

*/

DROP TABLE IF EXISTS corners;

CREATE TABLE corners AS SELECT row_number() over() AS id,
                               geom,
                               array_agg(id) AS sw_id,
                               array_agg(type) AS sw_type,
                               ST_Collect(s_geom) AS s_geom,
                               count(id) AS num_sw
                          FROM (SELECT ST_Startpoint(geom) AS geom,
                                       id,
                                       'S' AS type,
                                       geom AS s_geom
                                  FROM clean_sidewalks
                                 UNION
                                SELECT ST_Endpoint(geom) AS geom,
                                       id,
                                       'E' AS type,
                                       geom AS s_geom
                                  FROM clean_sidewalks) AS query
                      GROUP BY geom
                        HAVING geom IS NOT NULL;

CREATE INDEX corners_index
          ON corners
       USING gist(geom);

DROP TABLE IF EXISTS intersection_group;

CREATE TABLE intersection_group AS SELECT *
                                     FROM (SELECT DISTINCT ON (c.id) c.id AS c_id, -- end id
                                                                     i.id AS i_id, -- intersection id
                                                                     c.geom AS c_geom, -- end geom POINT
                                                                     i.geom AS i_geom,  -- intersection gesom POINT
                                                                     c.sw_type AS e_type,
                                                                     c.sw_id AS e_s_id,
                                                                     i.num_s AS i_type,
                                                                     c.s_geom AS s_geom
                                                         FROM corners AS c
                                                   INNER JOIN intersections AS i
                                                           ON ST_DWithin(c.geom, i.geom, 200)
                                                     ORDER BY c.id, ST_Distance(c.geom, i.geom)) AS q
                                 ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.c_geom);

UPDATE intersection_group
   SET i_id = result.i_id,
       i_geom = result.i_geom
  FROM (SELECT DISTINCT ON (q.c_id) q.c_id AS c_id,
                                    i.id AS i_id,
                                    i.geom AS i_geom
                      FROM (SELECT t1.*
                              FROM intersection_group t1,
                                   intersection_group t2
                             WHERE t1.i_id = t2.i_id
                               AND t1.e_s_id = t2.e_s_id
                               AND t1.e_type != t2.e_type
                               AND ST_Distance(t1.c_geom, t1.i_geom) > ST_Distance(t2.c_geom, t2.i_geom)) AS q
                 LEFT JOIN intersections AS i
                        ON i.id != q.i_id
                       AND ST_DWithin(q.c_geom, i.geom,200)
                  ORDER BY q.c_id, ST_Distance(q.c_geom, i.geom)) AS result
 WHERE result.c_id = intersection_group.c_id;

DELETE FROM intersection_group
      WHERE i_id IS NULL;


CREATE OR REPLACE FUNCTION find_corner_groups(degree double precision[], pointd double precision) RETURNS int AS
$$
BEGIN
FOR i IN 1..array_length(degree,1) LOOP
    IF pointd < degree[i] THEN
        RETURN i;
    END IF;
END LOOP;
IF pointd > degree[array_length(degree,1)] THEN
    RETURN 1;
ELSE
    RETURN -1;
END IF;
END
$$
LANGUAGE plpgsql;

ALTER TABLE intersection_group
 ADD COLUMN range_group int;

UPDATE intersection_group AS rig
   SET range_group = find_corner_groups(i.degree, ST_Azimuth(rig.i_geom, e.geom))
  FROM intersections AS i,
       corners AS e
 WHERE i.id = rig.i_id
   AND rig.c_id = e.id;



DROP TABLE IF EXISTS corner_group;

CREATE TABLE corner_group AS SELECT *
                               FROM (SELECT row_number() over() AS id,
                                            rig.i_id,
                                            rig.range_group,
                                            ST_Centroid(ST_Collect(rig.c_geom)) AS c_geom,
                                            ST_Collect(rig.s_geom) AS s_geom,
                                            -- FIXME: changed from 'num(c_id)', not sure if this is important
                                            count(rig.c_id) as count
                                       FROM intersection_group AS rig
                                   GROUP BY i_id,i_geom, range_group) AS q;

DROP TABLE IF EXISTS crossings;

CREATE TABLE crossings(id SERIAL PRIMARY KEY,
                        geom Geometry,
                        c1_id int,
                        c2_id int);

/* Generate crossings at Non-T intersections
FIXME: This is the section that is currently the most broken -
0 entries are updated (not crossings made)*/
/*
Logic: Generate cross join on all corner groups at an intersection,
       only make line joining a given pair if it crosses a street
*/
INSERT INTO crossings (geom, c1_id, c2_id)
     SELECT ST_MakeLine(q1.c_geom, q2.c_geom) as geom,
                        q1.id AS c1_id,
                        q2.id AS c2_id
       FROM (  SELECT corner_group.*,
                      intersections.degree_diff
                 FROM corner_group
                 JOIN intersections
                   ON intersections.id = corner_group.i_id
                WHERE intersections.is_t IS FALSE
                  AND num_s > 3) AS q1,
            (  SELECT corner_group.*,
                      intersections.degree_diff
                 FROM corner_group
                 JOIN intersections
                   ON intersections.id = corner_group.i_id
                WHERE intersections.is_t IS FALSE AND num_s > 3) AS q2,
            (  SELECT i_id,
                      count(range_group) as count /* Why make a bunch of these? All the same value */
                 FROM corner_group
             GROUP BY i_id) AS num
      WHERE num.i_id = q1.i_id
        AND q1.i_id = q2.i_id
        AND (q1.range_group + 1 = q2.range_group /* clockwise */OR
             q1.range_group/num.count = q2.range_group);

INSERT INTO crossings (geom, c1_id, c2_id)
     SELECT ST_MakeLine(q1.c_geom, q2.c_geom),
            q1.id AS c1_id,
            q2.id AS c2_id
       FROM (SELECT cg.*,
                    i.degree_diff
               FROM corner_group AS cg
               JOIN intersections AS i
                 ON i.id = cg.i_id
              WHERE i.is_t
                AND num_s >= 3
                AND i.degree_diff[4] != cg.range_group) AS q1,
            (SELECT cg.*,
                    i.degree_diff
               FROM corner_group AS cg
               JOIN intersections AS i
                 ON i.id = cg.i_id
              WHERE i.is_t
                AND num_s >= 3
                AND i.degree_diff[4] != cg.range_group) AS q2,
            (  SELECT i_id,
                      count(range_group) AS count
                 FROM corner_group
             GROUP BY i_id) AS num
      WHERE num.i_id = q1.i_id
        AND q1.i_id = q2.i_id
        AND (q1.range_group + 1 = q2.range_group
         OR q1.range_group/num.count = q2.range_group);

INSERT INTO crossings (geom, c1_id, c2_id)
     SELECT ST_ShortestLine(q1.s_geom, q2.c_geom) as geom,
            q1.id AS c1_id,
            q2.id AS c2_id
       FROM (SELECT cg.*,
                    i.degree_diff
               FROM corner_group AS cg
               JOIN intersections AS i
                 ON i.id = cg.i_id
              WHERE i.is_t
                AND num_s >= 3
                AND i.degree_diff[4] = cg.range_group) AS q1,
            (SELECT cg.*,
                    i.degree_diff
               FROM corner_group AS cg
               JOIN intersections AS i
                 ON i.id = cg.i_id
              WHERE i.is_t
                AND num_s >= 3
                AND i.degree_diff[4] != cg.range_group) AS q2,
            (  SELECT i_id,
                      count(range_group) AS count
                 FROM corner_group
             GROUP BY i_id) AS num
      WHERE num.i_id = q1.i_id
        AND q1.i_id = q2.i_id
        AND (q1.range_group + 1 = q2.range_group
             OR q1.range_group - 1 = q2.range_group
             OR q1.range_group/num.count = q2.range_group
             OR q2.range_group/num.count = q1.range_group);

/* Remove crossings that intersect more than one street (usually incorrect
crossings e.g. ones that go across an intersection diagonally) */
DELETE FROM crossings
WHERE id IN (SELECT counts.crossings_id
               FROM (SELECT c.id AS crossings_id,
                            count(c.id) AS num
                       FROM streets AS s,
                            crossings AS c
                       WHERE ST_Intersects(s.geom, c.geom)
                    GROUP BY (c.id)) AS counts
              WHERE counts.num > 1);
