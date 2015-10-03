-----------------------------------------
--- Step 1: Create end intersection groups
-----------------------------------------
--- Get sidewalks corners table
-- TODO: check why some sidewalks with starting point return false
DROP TABLE IF EXISTS sidewalk_ends;
CREATE TABLE sidewalk_ends AS
	SELECT
		row_number() over() as id,
		geom,
		query.id as sw_id,
		type as sw_type,
		other as sw_other
	FROM
	(
		SELECT
			ST_Startpoint(geom) as geom,
			id,
			'S' as type,
			 ST_PointN(geom,2) as other
		FROM
			sidewalks
		WHERE
			ST_Startpoint(geom) is not null
		UNION
		SELECT
			ST_Endpoint(geom) as geom,
			id,
			'E' as type,
			ST_PointN(geom,ST_NPoints(geom) - 1)  as other
		FROM
			sidewalks
		WHERE
			ST_Endpoint(geom) is not null
	) as query;
CREATE INDEX sidewalk_ends_index ON sidewalk_ends USING gist(geom);


DROP TABLE IF EXISTS intersection_groups;
CREATE TABLE intersection_groups AS
	SELECT *
	FROM
	(
		SELECT
			DISTINCT ON (e.id)
			e.id as e_id, -- end id
			i.id as i_id, -- intersection id
			e.geom as e_geom, -- end geom POINT
			i.geom as i_geom,  -- intersection geom POINT
			e.sw_type as e_type,
			e.sw_id as e_s_id
		FROM
			sidewalk_ends as e
			INNER JOIN (SELECT * FROM intersections WHERE num_s > 1) AS i
				ON ST_DWithin(e.geom, i.geom, 200)
		ORDER BY e.id, ST_Distance(e.geom, i.geom)
	) AS q
	ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.e_geom);

-- TODO: remove the same assignment for each sidewalks
-- There are 408 sidewalks classified in the same group

UPDATE intersection_groups
SET
	i_id = result.i_id,
	i_geom = result.i_geom
FROM(
	SELECT DISTINCT ON (q.e_id)
		q.e_id as e_id,
		i.id as i_id,
		i.geom as i_geom
	FROM(
		SELECT t1.*
		FROM intersection_groups t1, intersection_groups t2
		WHERE
			t1.i_id = t2.i_id
			and t1.e_s_id = t2.e_s_id
			and t1.e_type!=t2.e_type
			and ST_Distance(t1.e_geom, t1.i_geom) > ST_Distance(t2.e_geom, t2.i_geom)
	) AS q
LEFT JOIN intersections AS i
	ON i.id != q.i_id
	AND ST_DWithin(q.e_geom, i.geom,200)
ORDER BY q.e_id, ST_Distance(q.e_geom,i.geom)
) AS result
WHERE result.e_id = intersection_groups.e_id;

DELETE FROM intersection_groups
WHERE i_id is null;

--- Step4: group by corners
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

ALTER TABLE intersection_groups
	ADD COLUMN range_group int;

UPDATE intersection_groups as rig
SET range_group = find_corner_groups(i.degree, ST_Azimuth(rig.i_geom, ST_Line_Interpolate_Point(st_makeline(e.geom, e.sw_other),0.9)))
FROM intersections as i, sidewalk_ends as e
WHERE i.id = rig.i_id AND rig.e_id = e.id;


-- Step2: Clean sidewalks inside each pair
DROP TABLE IF EXISTS intersection_groups_ready CASCADE;
CREATE TABLE intersection_groups_ready AS
	SELECT
		row_number() over() as id,
		i_geom,
		rig.i_id,
		rig.range_group,
		array_agg(rig.e_geom) as e_geom,
		array_agg(rig.e_type) as s_type,
		array_agg(rig.e_s_id) as s_id,
		array_agg(s.geom) as s_geom,
		false as isCleaned,
		count(e_id) as size
	FROM
		intersection_groups as rig
	INNER JOIN sidewalks as s
		ON s.id = rig.e_s_id
	GROUP BY i_id,  i_geom, range_group;


/*
Create a table to store the cleaned sidewalks after step 2
*/

DROP TABLE clean_sidewalks CASCADE;
CREATE TABLE clean_sidewalks AS
SELECT * FROM sidewalks;

ALTER TABLE clean_sidewalks
	ADD PRIMARY KEY (id);
CREATE INDEX index_clean_sidewalks ON clean_sidewalks USING gist(geom);

UPDATE clean_sidewalks
SET s_changed = False, e_changed = False;

/* Function: Find the intersection of two geometries and find the closet point to i among the intersections
Params: g1, g2 geometry "the comparing geometries"
i geometry "the geometry of the intersection"
*/
CREATE OR REPLACE FUNCTION find_intersection_point(g1 geometry,g2 geometry,i geometry) RETURNS geometry AS
$$
DECLARE
	inter_point RECORD;
	inter_line RECORD;
BEGIN
	/* Find the intersections that is closest to i */
	SELECT *
	FROM
	(
		SELECT (ST_dump(ST_Intersection(g1, g2))).geom
	) as q
	ORDER BY ST_Distance(i, q.geom)
	LIMIT 1
	INTO inter_point;

	/* Discuss the type of the intersections */
	IF geometrytype(inter_point.geom) = 'POINT' THEN
		RETURN inter_point.geom;
	/* If the intersection is a linestring, the find the point that is farthest to the i */
	ELSEIF geometrytype(inter_point.geom) = 'LINESTRING' THEN
		SELECT *
		FROM (
			SELECT (ST_Dumppoints(inter_point.geom)).geom
		) as q
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


CREATE OR REPLACE FUNCTION trim_lines(s_id int/*intersection*/,i geometry,e text/* side to discard*/, s_geom geometry) RETURNS void AS
$$
DECLARE i_f float;
--DECLARE s RECORD;
BEGIN
	/*
	IF s_geom is null THEN
		SELECT geom FROM clean_sidewalks WHERE id = s_id INTO s AND geometrytype(geom) = 'LINESTRING';
		i_f := ST_Line_Locate_Point(s.geom, i);
	ELSE
	*/
	i_f := ST_Line_Locate_Point(s_geom, i);
	IF e = 'E' THEN
		UPDATE clean_sidewalks SET geom = ST_Line_Substring(s_geom, 0, i_f),e_changed = true WHERE id = s_id;
	ELSE
		UPDATE clean_sidewalks SET geom = ST_Line_Substring(s_geom, i_f, 1),s_changed = true WHERE id = s_id;
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
true if two lines intersects and have been trimmed.
*/

CREATE OR REPLACE FUNCTION trim_pairs(s1_id int, s2_id int, e1 text, e2 text, i geometry) RETURNS boolean AS
$$
DECLARE s1 RECORD;
DECLARE s2 RECORD;
DECLARE s1_geom geometry;
DECLARE s2_geom geometry;
DECLARE inter_point geometry;
BEGIN
	/* Find the geometry from cleaned_sidewalks*/
	SELECT geom FROM clean_sidewalks WHERE id = s1_id INTO s1;
	SELECT geom FROM clean_sidewalks WHERE id = s2_id INTO s2;
	/* If two function intersects, trim */
	IF ST_Intersects(s1.geom, s2.geom) THEN
		/* Find the intersection point*/
		inter_point := find_intersection_point(s1.geom,s2.geom, i);
		/* Trim s1 and s2*/
		PERFORM trim_lines(s1_id, inter_point, e1, s1.geom);
		PERFORM trim_lines(s2_id, inter_point, e2, s2.geom);
		RETURN True;
	ELSE
		RETURN False;
	END IF;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION extend_pairs(s1_id int, s2_id int, e1 text, e2 text, i geometry) RETURNS boolean AS
$$
DECLARE s1 RECORD;
DECLARE s2 RECORD;
DECLARE s1_geom geometry;
DECLARE s2_geom geometry;
DECLARE inter_point geometry;
BEGIN
	SELECT geom FROM clean_sidewalks WHERE id = s1_id INTO s1;
	SELECT geom FROM clean_sidewalks WHERE id = s2_id INTO s2;
	s1_geom:= extend_line(s1.geom,i,e1);
	s2_geom:= extend_line(s2.geom,i,e2);
	/* use st_relate instead of st_intersects to avoid spatial index*/
	IF st_relate(s1_geom, s2_geom,'FF*FF****') = False THEN
		inter_point := find_intersection_point(s1_geom,s2_geom, i);
		PERFORM trim_lines(s1_id, inter_point, e1, s1_geom);
		PERFORM trim_lines(s2_id, inter_point, e2, s2_geom);
		RETURN True;
	ELSE
		RETURN False;
	END IF;
END
$$
LANGUAGE plpgsql;


--DROP FUNCTION merge_to_middle_point(s_id int[], s_type text[], centroid geometry, s_geom geometry[], size int)
CREATE OR REPLACE FUNCTION merge_to_middle_point(s_id int[], s_type text[], centroid geometry, s_geom geometry[], size bigint) RETURNS boolean AS
$$
BEGIN
	FOR i IN 1..size LOOP
    	IF s_type[i] = 'E' THEN
    		UPDATE clean_sidewalks SET geom = ST_Addpoint(s_geom[i],centroid), e_changed = true WHERE id = s_id[i];
    	ELSE
    		UPDATE clean_sidewalks SET geom = ST_Addpoint(s_geom[i],centroid,0), s_changed = true WHERE id = s_id[i];
    	END IF;
	END LOOP;
	RETURN TRUE;
END
$$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION extend_line(s geometry, i geometry, type text) RETURNS geometry AS
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

DROP TABLE intersection_groups_ready CASCADE;
CREATE TABLE intersection_groups_ready AS
	SELECT
		row_number() over() as id,
		i_geom,
		rig.i_id,
		rig.range_group,
		array_agg(rig.e_geom) as e_geom,
		array_agg(rig.e_type) as s_type,
		array_agg(rig.e_s_id) as s_id,
		array_agg(s.geom) as s_geom,
		false as isCleaned,
		count(e_id) as size
	FROM
		intersection_groups as rig
	INNER JOIN sidewalks as s
		ON s.id = rig.e_s_id
	GROUP BY i_id,  i_geom, range_group;

DROP TABLE clean_sidewalks CASCADE;
CREATE TABLE clean_sidewalks AS
SELECT * FROM sidewalks;

ALTER TABLE clean_sidewalks
	ADD PRIMARY KEY (id);
CREATE INDEX index_clean_sidewalks ON clean_sidewalks USING gist(geom);

UPDATE clean_sidewalks
SET s_changed = False, e_changed = False;



UPDATE intersection_groups_ready
SET isCleaned = false;

UPDATE intersection_groups_ready
SET isCleaned = true
WHERE size = 2 AND ST_Equals(e_geom[1],e_geom[2]);

UPDATE intersection_groups_ready
SET isCleaned = true
WHERE size = 1;

UPDATE intersection_groups_ready
SET isCleaned = trim_pairs(s_id[1], s_id[2],s_type[1], s_type[2], i_geom)
WHERE isCleaned = false AND size = 2;

UPDATE intersection_groups_ready
SET isCleaned = extend_pairs(s_id[1], s_id[2],s_type[1], s_type[2], i_geom)
WHERE isCleaned = false AND size = 2;

UPDATE intersection_groups_ready
SET isCleaned = merge_to_middle_point(s_id, s_type,st_centroid(st_collect(e_geom)), s_geom, size)
WHERE isCleaned = false AND size = 2;

DROP TABLE intersection_groups;
DROP TABLE intersection_groups_ready;
DROP TABLE sidewalk_ends;
