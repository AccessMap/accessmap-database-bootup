-- Drop tables created in this step prior to recreating them
DROP TABLE IF EXISTS build.sidewalk_ends;
DROP TABLE IF EXISTS build.intersection_groups;
DROP TABLE IF EXISTS build.intersection_groups_ready CASCADE;
DROP TABLE IF EXISTS build.clean_sidewalks CASCADE;

/*
Create the build.sidewalk_ends table to contain sidewalk startpoint and endpoint
information, generally creating 2 rows in build.sidewalk_ends for every row in
the original sidewalks table.
    columns:
        id: (non-unique) row count (I think) TODO: replace with new primary key
            generator
        geom: Point geometry representing either a sidewalk start or end point
        sw_id: id of the associated sidewalk (should be a foreign key?)
        sw_type: either 'S' for start or 'E' for end - which endpoint of the
                 sidewalk it's on
        sw_other: Point geometry representing the nearest point to the start or
                  end - useful for generating direction the sidwalk end is
                  pointing
*/

-- TODO: check why some sidewalks with starting point return FALSE
CREATE TABLE build.sidewalk_ends AS
      SELECT row_number() OVER () AS id,
             geom,
             query.id AS sw_id,
             -- FIXME: 'type' is a keyword,
             -- build.sidewalk_ends shouldn't have it as a
             -- column
             type AS sw_type,
             other AS sw_other
        FROM (SELECT ST_Startpoint(geom) AS geom,
                     id,
                     'S' AS type,
                     ST_PointN(geom, 2) AS other
                FROM data.sidewalks
               WHERE ST_Startpoint(geom) IS NOT NULL
               UNION
              SELECT ST_Endpoint(geom) AS geom,
                     id,
                     'E' AS type,
                     ST_PointN(geom, ST_NPoints(geom) - 1) AS other
                FROM data.sidewalks
               WHERE ST_Endpoint(geom) IS NOT NULL) AS query;

CREATE INDEX sidewalk_ends_index
          ON build.sidewalk_ends
       USING gist(geom);

--
-- Create intersections table - based on where street network has intersections
--

-- CREATE TABLE build.intersections AS
--       SELECT ST_Intersection(st1.geom, st2.geom) AS geom
--         FROM data.streets st1
--         JOIN data.streets st2
--           ON ST_Intersects(st1.geom, st2.geom)
--        WHERE st1.id != st2.id;
--
-- ALTER TABLE build.intersections ADD COLUMN id SERIAL PRIMARY KEY;

/*
Create build.intersection_groups table - build.sidewalk_ends are associated with an
intersection
    Columns:
        e_id: sidewalk_end table row id
        i_id: intersections table row id - an intersection
        e_geom: geom (Point) of the sidewalk_end row
        i_geom: geom (Point) of the intersections row
        e_type: 'type' of endpoint ('S' for start, 'E' for end, relative to the
                geom)
        e_s_id: s_id column of the sidewalk_end row - the ID of the sidewalk
                (from the sidewalks table) associated with the end point
    TODO: ensure uniqueness of endpoint-intersection association? Can an
          endpoint belong to more than one intersection and vice versa?
*/
-- TODO: figure out what units are for ST_DWithin - relies on SRID
CREATE TABLE build.intersection_groups AS
      SELECT *
        FROM (SELECT DISTINCT ON (e.id) e.id AS e_id, -- end id
                                        i.id AS i_id, -- intersection id
                                        e.geom AS e_geom, -- end geom POINT
                                        i.geom AS i_geom,  -- intersection geom POINT
                                        e.sw_type AS e_type,
                                        e.sw_id AS e_s_id
                            FROM build.sidewalk_ends e
                      INNER JOIN (SELECT id,
                                         geom
                                    FROM build.intersections
                                   WHERE num_s > 1) i
                         ON ST_DWithin(e.geom, i.geom, 200)
                   ORDER BY e.id, ST_Distance(e.geom, i.geom)) AS q
    ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.e_geom);

/*
I'm not entirely sure what this is doing. It's changing the intersection ID
and geometry for some rows in build.intersection_groups but I don't understand the
logic. FIXME: understand and add comments for the logic below.
*/
UPDATE build.intersection_groups
   SET i_id = result.i_id,
       i_geom = result.i_geom
  FROM (SELECT DISTINCT ON (q.e_id) q.e_id AS e_id,
                                    i.id AS i_id,
                                    i.geom AS i_geom
                      -- Get the 'far' endpoint of each intersection group
                      FROM (SELECT t1.*
                              FROM build.intersection_groups t1,
                                   build.intersection_groups t2
                             WHERE t1.i_id = t2.i_id
                               -- Match being from the same sidewalk
                               AND t1.e_s_id = t2.e_s_id
                               -- Match only if StartPoint and Endpoint
                               AND t1.e_type!=t2.e_type
                               -- Filter by the first geom being farther
                               -- away from intersection, ensuring that
                               -- columns selected come from the end farther
                               -- away from the intersection
                               AND ST_Distance(t1.e_geom, t1.i_geom) > ST_Distance(t2.e_geom, t2.i_geom)) AS q
                      JOIN build.intersections AS i
                        -- Join when intersection IDs *don't* match (?)
                        ON i.id != q.i_id
                        -- But the intersections still need to be closeby
                       AND ST_DWithin(q.e_geom, i.geom,200)
                  ORDER BY q.e_id, ST_Distance(q.e_geom, i.geom)) AS result
 WHERE result.e_id = build.intersection_groups.e_id;

-- Remove intersection groups for which there's no intersection
-- FIXME: (why do these exist in the first place - add comments after finding
--         out)
DELETE FROM build.intersection_groups
      WHERE i_id IS NULL;

--- Step4: group by corners
-- TODO: Update functions with style guide rules - not sure what to do for functions
CREATE OR REPLACE FUNCTION find_corner_groups(degree double precision[], pointd double precision)
RETURNS int AS
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

-- 'range_group' column - attempting to group corners at intersections by
-- block.
ALTER TABLE build.intersection_groups
 ADD COLUMN range_group int;

-- Update range group - find_corner_groups assigns as '1' or '-1' if it's
-- within the range specified. FIXME: what is the real purpose of this?
UPDATE build.intersection_groups AS rig
   SET range_group = find_corner_groups(i.degree, ST_Azimuth(rig.i_geom, ST_LineInterpolatePoint(ST_MakeLine(e.geom, e.sw_other), 0.9)))
  FROM build.intersections AS i,
       build.sidewalk_ends AS e
 WHERE i.id = rig.i_id
   AND rig.e_id = e.id;


-- Step2: Clean sidewalks inside each pair

/*
Create a table to store the cleaned sidewalks after step 2
*/


CREATE TABLE build.clean_sidewalks AS
      SELECT *
        FROM data.sidewalks;

ALTER TABLE build.clean_sidewalks
        ADD PRIMARY KEY (id);

CREATE INDEX index_clean_sidewalks
          ON build.clean_sidewalks
       USING gist(geom);

UPDATE build.clean_sidewalks
   SET s_changed = FALSE,
       e_changed = FALSE;

/* Function: Find the intersection of two geometries and find the closet point to i among the intersections
Params: g1, g2 geometry "the comparing geometries"
i geometry "the geometry of the intersection"
*/
CREATE OR REPLACE FUNCTION find_intersection_point(g1 geometry,g2 geometry,i geometry)
RETURNS geometry AS
$$
DECLARE
    inter_point RECORD;
    inter_line RECORD;
BEGIN
    /* Find the intersections that is closest to i */
      SELECT *
        FROM (SELECT (ST_dump(ST_Intersection(g1, g2))).geom) AS q
    ORDER BY ST_Distance(i, q.geom)
       LIMIT 1
        INTO inter_point;

      /* Discuss the type of the intersections */
    IF geometrytype(inter_point.geom) = 'POINT'
    THEN
        RETURN inter_point.geom;
       /* If the intersection is a linestring, the find the point that
          is farthest to the i */
    ELSEIF geometrytype(inter_point.geom) = 'LINESTRING'
    THEN
          SELECT *
            FROM (SELECT (ST_Dumppoints(inter_point.geom)).geom) AS q
        ORDER BY ST_Distance(i, q.geom) DESC
           LIMIT 1
            INTO inter_line;

        RETURN inter_line.geom;
    ELSE
        RETURN NULL;
    END IF;

    RETURN inter_point.geom;
END
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION trim_lines(s_id int/*intersection*/,i geometry,e text/* side to discard*/, s_geom geometry)
RETURNS void AS
$$
DECLARE i_f float;
--DECLARE s RECORD;
BEGIN
    /*
    IF s_geom is null THEN
        SELECT geom FROM build.clean_sidewalks WHERE id = s_id INTO s AND geometrytype(geom) = 'LINESTRING';
        i_f := ST_LineLocatePoint(s.geom, i);
    ELSE
    */
    i_f := ST_LineLocatePoint(s_geom, i);
    IF e = 'E'
    THEN
         UPDATE build.clean_sidewalks
            SET geom = ST_LineSubstring(s_geom, 0, i_f),
                e_changed = TRUE
          WHERE id = s_id;
    ELSE
         UPDATE build.clean_sidewalks
            SET geom = ST_LineSubstring(s_geom, i_f, 1),
                s_changed = TRUE
          WHERE id = s_id;
    END IF;
END
$$
LANGUAGE plpgsql;


/* Find all intersecting pair of lines and trim them to the intersection
Params:
s1_id int, s2_id int "id of sidewalks that needs trimming"
e1 text, e2 text "side of sidewalks needs trimming E stands for endpoint, S stands for startpoint"
i geometry "geometry of street intersection point"
Returns:
TRUE if two lines intersects and have been trimmed.
*/

CREATE OR REPLACE FUNCTION trim_pairs(s1_id int, s2_id int, e1 text, e2 text, i geometry)
RETURNS boolean AS
$$
DECLARE s1 RECORD;
DECLARE s2 RECORD;
DECLARE s1_geom geometry;
DECLARE s2_geom geometry;
DECLARE inter_point geometry;
BEGIN
    /* Find the geometry from cleaned_sidewalks*/
    SELECT geom
      FROM build.clean_sidewalks
     WHERE id = s1_id
      INTO s1;

    SELECT geom
      FROM build.clean_sidewalks
     WHERE id = s2_id
      INTO s2;

    /* If two function intersects, trim */
    IF ST_Intersects(s1.geom, s2.geom)
    THEN
        /* Find the intersection point*/
        inter_point := find_intersection_point(s1.geom,s2.geom, i);
        /* Trim s1 and s2*/
        PERFORM trim_lines(s1_id, inter_point, e1, s1.geom);
        PERFORM trim_lines(s2_id, inter_point, e2, s2.geom);
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION extend_pairs(s1_id int, s2_id int, e1 text, e2 text, i geometry)
RETURNS boolean AS
$$
DECLARE s1 RECORD;
DECLARE s2 RECORD;
DECLARE s1_geom geometry;
DECLARE s2_geom geometry;
DECLARE inter_point geometry;
BEGIN
    SELECT geom
      FROM build.clean_sidewalks
     WHERE id = s1_id
      INTO s1;

    SELECT geom
      FROM build.clean_sidewalks
     WHERE id = s2_id
      INTO s2;

    s1_geom:= extend_line(s1.geom,i,e1);
    s2_geom:= extend_line(s2.geom,i,e2);
    /* use ST_Relate instead of ST_Intersects to avoid spatial index*/
    IF ST_Relate(s1_geom, s2_geom,'FF*FF****') = FALSE
    THEN
        inter_point := find_intersection_point(s1_geom,s2_geom, i);
        PERFORM trim_lines(s1_id, inter_point, e1, s1_geom);
        PERFORM trim_lines(s2_id, inter_point, e2, s2_geom);
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
LANGUAGE plpgsql;


--DROP FUNCTION merge_to_middle_point(s_id int[], s_type text[], centroid geometry, s_geom geometry[], size int)
CREATE OR REPLACE FUNCTION merge_to_middle_point(s_id int[], s_type text[], centroid geometry, s_geom geometry[], size bigint)
RETURNS boolean AS
$$
BEGIN
    FOR i IN 1..size LOOP
        IF s_type[i] = 'E' THEN
            UPDATE build.clean_sidewalks
               SET geom = ST_Addpoint(s_geom[i],centroid),
                   e_changed = TRUE
             WHERE id = s_id[i];
        ELSE
            UPDATE build.clean_sidewalks
               SET geom = ST_Addpoint(s_geom[i],centroid,0),
                   s_changed = TRUE
             WHERE id = s_id[i];
        END IF;
    END LOOP;

    RETURN TRUE;
END
$$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION extend_line(s geometry, i geometry, type text)
RETURNS geometry AS
$$
DECLARE az double precision;
DECLARE length double precision;
DECLARE a geometry;
DECLARE b geometry;
BEGIN
    -- get the points A and B given a line L
    IF type = 'E' THEN
        a := ST_PointN(s,ST_Npoints(s));
        b := ST_PointN(s,ST_Npoints(s) - 1);
        az:= ST_Azimuth(b,a);
        length := ST_DISTANCE(a,i);
        RETURN ST_Addpoint(s, ST_TRANSLATE(a, sin(az) * length, cos(az) * length));
    ELSE
        a := ST_PointN(s,1);
        b := ST_PointN(s,2);
        az:= ST_Azimuth(b,a);
        length := ST_DISTANCE(a,i);
        RETURN ST_Addpoint(s, ST_TRANSLATE(a, sin(az) * length, cos(az) * length),0);
    END IF;
END
$$
LANGUAGE plpgsql;


CREATE TABLE build.intersection_groups_ready AS
      SELECT row_number() over() AS id,
             i_geom,
             rig.i_id,
             rig.range_group,
             array_agg(rig.e_geom) AS e_geom,
             array_agg(rig.e_type) AS s_type,
             array_agg(rig.e_s_id) AS s_id,
             array_agg(s.geom) AS s_geom,
             -- FIXME: 'FALSE' and 'size' are reserved keywords
             FALSE AS isCleaned,
             count(e_id) AS size
        FROM build.intersection_groups AS rig
  INNER JOIN data.sidewalks AS s
          ON s.id = rig.e_s_id
    GROUP BY i_id, i_geom, range_group;

UPDATE build.intersection_groups_ready
   SET isCleaned = FALSE;

UPDATE build.intersection_groups_ready
   SET isCleaned = TRUE
 -- FIXME: 'size' is a reserved keyword
 WHERE size = 2
   AND ST_Equals(e_geom[1], e_geom[2]);

UPDATE build.intersection_groups_ready
   SET isCleaned = TRUE
 -- FIXME: 'size' is a resreved keyword
 WHERE size = 1;

UPDATE build.intersection_groups_ready
   SET isCleaned = trim_pairs(s_id[1], s_id[2],s_type[1], s_type[2], i_geom)
 -- FIXME: 'size' is a resreved keyword
 WHERE isCleaned = FALSE
   AND size = 2;

UPDATE build.intersection_groups_ready
   SET isCleaned = extend_pairs(s_id[1], s_id[2],s_type[1], s_type[2], i_geom)
 -- FIXME: 'size' is a resreved keyword
 WHERE isCleaned = FALSE
   AND size = 2;

UPDATE build.intersection_groups_ready
   SET isCleaned = FALSE
 -- FIXME: 'size' is a reserved keyword
 WHERE size = 1;

UPDATE build.intersection_groups_ready
   -- FIXME: 'size' is a reserved keyword
   SET isCleaned = merge_to_middle_point(s_id, s_type, ST_Centroid(ST_Collect(e_geom)), s_geom, size)
 WHERE isCleaned = FALSE
   AND size = 2;

-- Drop temporary tables
DROP TABLE build.intersection_groups;
DROP TABLE build.intersection_groups_ready;
DROP TABLE build.sidewalk_ends;
