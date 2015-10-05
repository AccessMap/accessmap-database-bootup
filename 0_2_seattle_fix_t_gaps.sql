-- TODO: refactor to remove redundant intermediate steps
-----------------------------------------------------------------------------
-- Step 1: Function to find the largest angle between streets in intersection
-----------------------------------------------------------------------------
-- Note: The difference of the max_degree and min_degree IS calculated after
--       mod 2 * pi.

CREATE OR REPLACE FUNCTION Find_Maximum_Degree_Diff(a_degree double precision[], count bigint) RETURNS double precision[] AS
$$
DECLARE max_degree double precision;
DECLARE cur_degree double precision;
DECLARE len int;
DECLARE result double precision[4];
BEGIN
    len := count;
    max_degree := 0;
    FOR i in 1..len-1 LOOP
        cur_degree := a_degree[i + 1] - a_degree[i];
        IF cur_degree > max_degree THEN max_degree := cur_degree;result[1] := a_degree[i];result[2] := a_degree[i + 1];result[4] := i + 1;
        END IF;
    END LOOP;
        cur_degree := a_degree[1] - a_degree[len] + 2 * pi();
        IF cur_degree > max_degree THEN max_degree := cur_degree;result[1] := a_degree[len];result[2] := a_degree[1];result[4] := 1;
        END IF;
    result[3] := max_degree;
    RETURN result;
END
$$
LANGUAGE plpgsql;


------------------------------------------------------
-- Step 2: Find the largest angle at each intersection
------------------------------------------------------

ALTER TABLE intersections
DROP COLUMN
         IF EXISTS degree_diff;

ALTER TABLE intersections
 ADD COLUMN degree_diff double precision[];

UPDATE intersections
   SET degree_diff = Find_Maximum_Degree_Diff(degree, num_s);

ALTER TABLE intersections
DROP COLUMN
         IF EXISTS is_t;

ALTER TABLE intersections
 ADD COLUMN is_t boolean DEFAULT FALSE;

UPDATE intersections
   SET is_t = TRUE
 WHERE num_s >= 3
   AND degrees(degree_diff[3]) > 170
   AND degrees(degree_diff[3]) < 190;


-------------------------------------------------
-- Step 3: sidewalk corners & intersection groups
-------------------------------------------------
--- Get sidewalks corners table
-- TODO: check why some sidewalks with starting point return false
DROP TABLE
        IF EXISTS sidewalk_ends;

CREATE TABLE sidewalk_ends AS SELECT row_number() over() AS id,
                                     geom,
                                     query.id AS sw_id,
                                     type AS sw_type,
                                     other AS sw_other
                                FROM (SELECT ST_Startpoint(geom) AS geom,
                                             id,
                                             'S' AS type,
                                             ST_PointN(geom,2) AS other
                                        FROM sidewalks
                                       WHERE ST_Startpoint(geom) IS NOT NULL
                                UNION SELECT ST_Endpoint(geom) AS geom,
                                             id,
                                             'E' AS type,
                                             ST_PointN(geom,ST_NPoints(geom) - 1) AS other
                                        FROM sidewalks
                                       WHERE ST_Endpoint(geom) IS NOT NULL) AS query;

CREATE INDEX sidewalk_ends_index
          ON sidewalk_ends
       USING gist(geom);

-- Assign sidewalk ends to intersection groups
/*
Note:
1. Only intersections have assigned corners exist in this table.
2. Only ends assigned to any intersections table exist in this table.
3. The measurement of the distance tolerance IS feet.
TODO:
1. Discuss dead End, t-intersection and L-intersection cases.
2. same line assign to the same group
*/
-- Define intersection groups;
DROP TABLE IF EXISTS intersection_groups;

CREATE TABLE intersection_groups AS SELECT *
                                      FROM (SELECT DISTINCT ON (e.id) e.id AS e_id, -- end id
                                                                      i.id AS i_id, -- intersection id
                                                                      e.geom AS e_geom, -- end geom POINT
                                                                      i.geom AS i_geom  -- intersection geom POINT
                                                          FROM sidewalk_ends AS e
                                                    INNER JOIN intersections AS i
                                                            ON ST_DWithin(e.geom, i.geom, 100)
                                                      ORDER BY e.id, ST_Distance(e.geom, i.geom)) AS q
                                  ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.e_geom);


-----------------------------------------------------
-- Step 4: Fix T-intersections by extending sidewalks
-----------------------------------------------------
-- Connect gaps in T-intersections
-- Function to decide whether number IS between two other numbers?
CREATE OR REPLACE FUNCTION is_point_in_range(dg_range double precision[], dg_point double precision) RETURNS boolean AS
$$
BEGIN
    IF dg_range[2] > dg_range[1] THEN
        IF dg_point < dg_range[2] AND dg_point > dg_range[1] THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    ELSE
        IF dg_point < dg_range[2] OR dg_point > dg_range[1] THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END IF;
  END
$$
LANGUAGE plpgsql;

/* Find all gaps in T intersections
Pre: yun_intersections, yun_intersection_group, yun_corner
Post: inter_groups
Note:
I only consider the case where(#corners = 2 & #sum_sw = 2). However, other cases are also solvable. Details see Test in QGIS below.
TODO:
consider other cases.
*/

DROP TABLE IF EXISTS inter_groups;

CREATE TABLE inter_groups AS SELECT t_ig.i_id,
                                    array_agg(e.sw_id) AS s_id,
                                    array_agg(e.sw_type) AS s_type,
                                    array_agg(e.geom) AS c_geom
                               FROM (    SELECT ig.*,degree_diff
                                           FROM (SELECT id,
                                                        degree_diff
                                                   FROM intersections
                                                  WHERE is_t = TRUE) AS ti -- All t intersections
                                     INNER JOIN intersection_groups AS ig
                                             ON ig.i_id = ti.id
                                          WHERE is_point_in_range(degree_diff,ST_Azimuth(ig.i_geom, ig.e_geom)) = TRUE) AS t_ig
                         INNER JOIN sidewalk_ends AS e
                                 ON t_ig.e_id = e.id
                              WHERE is_point_in_range(t_ig.degree_diff,ST_Azimuth(t_ig.i_geom, ST_Centroid(e.geom)))
                           GROUP BY t_ig.i_id
                             HAVING count(t_ig.e_id) = 2;

DROP TABLE IF EXISTS t_gap_flags;

CREATE TABLE t_gap_flags AS SELECT t_ig.i_id,
                                   array_agg(e.sw_id) AS s_id,
                                   array_agg(e.sw_type) AS s_type,
                                   array_agg(e.geom) AS c_geom
                              FROM (    SELECT ig.*,degree_diff
                                          FROM (SELECT id,
                                                       degree_diff
                                                  FROM intersections
                                                 WHERE is_t = TRUE) AS ti -- All t intersections
                                    INNER JOIN intersection_groups AS ig
                                            ON ig.i_id = ti.id
                                         WHERE is_point_in_range(degree_diff, ST_Azimuth(ig.i_geom, ig.e_geom)) = TRUE) AS t_ig
                        INNER JOIN sidewalk_ends AS e
                                ON t_ig.e_id = e.id
                             WHERE is_point_in_range(t_ig.degree_diff,ST_Azimuth(t_ig.i_geom, ST_Centroid(e.geom)))
                          GROUP BY t_ig.i_id
                            HAVING count(t_ig.e_id) != 2;


------------------------------------------------------
-- Step 5: Update sidewalks table with T intersections
------------------------------------------------------

/*
Insert the middle point of corners to the sidewalks
Pre:inter_groups, yun_cleaned_sidewalks
Post: yun_cleaned_sidewalks: updated geom, updated geom_changed
*/

/* Update first corner if it IS the ending point of a sidewalk */
UPDATE sidewalks AS s
   SET geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom))),
       e_changed = TRUE
  FROM inter_groups AS tig
 WHERE s.id = tig.s_id[1]
   AND tig.s_type[1] = 'E';

/* Update first corner if it IS the Starting point of a sidewalk */
UPDATE sidewalks AS s
   SET geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom)), 0),
       s_changed = TRUE
  FROM inter_groups AS tig
 WHERE s.id = tig.s_id[1]
   AND tig.s_type[1] = 'S';

/* Update second corner if it IS the ending point of a sidewalk */
UPDATE sidewalks AS s
   SET geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom))),
       e_changed = TRUE
 FROM inter_groups AS tig
WHERE s.id = tig.s_id[2]
  AND tig.s_type[2] = 'E';

/* Update first corner if it IS the Starting point of a sidewalk */
UPDATE sidewalks AS s
   SET geom = ST_AddPoint(geom, ST_Centroid(ST_Collect(tig.c_geom)),0),
       s_changed = TRUE
  FROM inter_groups AS tig
 WHERE s.id = tig.s_id[2]
   AND tig.s_type[2] = 'S';


--------------------------------
-- Step 6: Drop temporary tables
--------------------------------
DROP TABLE inter_groups;
DROP TABLE intersection_groups;
DROP TABLE sidewalk_ends;
DROP TABLE t_gap_flags;
