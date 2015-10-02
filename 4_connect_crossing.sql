DROP TABLE IF EXISTS yun_corners;
CREATE TABLE yun_corners AS
	SELECT  
		row_number() over() as id, 
		geom, 
		array_agg(id) as sw_id,
		array_agg(type) as sw_type,
		st_collect(s_geom) as s_geom, 
		count(id) as num_sw 
	FROM
	(
		SELECT 
			ST_Startpoint(geom) as geom, 
			id, 
			'S' as type,
			geom as s_geom 
		FROM 
			yun_cleaned_sidewalks
		UNION 
		SELECT 
			ST_Endpoint(geom) as geom, 
			id, 
			'E' as type,
			geom as s_geom
		FROM 
			yun_cleaned_sidewalks
	) as query
	Group BY geom HAVING geom is not null;
/************  49160 rows **************/
/* Create spatial index*/
CREATE INDEX index_yun_corners ON yun_corners USING gist(geom);

DROP TABLE IF EXISTS yun_intersection_group;
CREATE TABLE yun_intersection_group AS
	SELECT * 
	FROM
	(
		SELECT 
			DISTINCT ON (c.id) 
			c.id as c_id, -- end id
			i.id as i_id, -- intersection id
			c.geom as c_geom, -- end geom POINT
			i.geom as i_geom,  -- intersection gesom POINT
			c.sw_type as e_type,
			c.sw_id as e_s_id,
			i.num_s as i_type,
			c.s_geom as s_geom
		FROM 
			yun_corners as c
			INNER JOIN yun_intersections AS i 
				ON ST_DWithin(c.geom, i.geom, 200)
		ORDER BY c.id, ST_Distance(c.geom, i.geom) 
	)AS q
	ORDER BY q.i_id, ST_Azimuth(q.i_geom, q.c_geom);

UPDATE yun_intersection_group 
SET 
	i_id = result.i_id, 
	i_geom = result.i_geom
FROM(
	SELECT DISTINCT ON (q.c_id) 
		q.c_id as c_id, 
		i.id as i_id, 
		i.geom as i_geom 
	FROM(
		SELECT t1.* 
		FROM yun_intersection_group t1, yun_intersection_group t2
		WHERE 
			t1.i_id = t2.i_id 
			and t1.e_s_id = t2.e_s_id 
			and t1.e_type!=t2.e_type 
			and ST_Distance(t1.c_geom, t1.i_geom) > ST_Distance(t2.c_geom, t2.i_geom)
	) AS q
LEFT JOIN yun_intersections AS i
	ON i.id != q.i_id 
	AND ST_DWithin(q.c_geom, i.geom,200)
ORDER BY q.c_id, ST_Distance(q.c_geom,i.geom)
) AS result
WHERE result.c_id = yun_intersection_group.c_id;
/************* 201 row ********************/

DELETE FROM yun_intersection_group 
WHERE i_id is null;


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

ALTER TABLE yun_intersection_group
	ADD COLUMN range_group int;

UPDATE yun_intersection_group as rig
SET range_group = find_corner_groups(i.degree, ST_Azimuth(rig.i_geom, e.geom))
FROM yun_intersections as i, yun_corners as e
WHERE i.id = rig.i_id AND rig.c_id = e.id;



DROP TABLE IF EXISTS yun_corner_group;
CREATE TABLE yun_corner_group AS
SELECT * FROM (
	SELECT 
		row_number() over() as id,
		rig.i_id,
		rig.range_group, 
		st_centroid(st_collect(rig.c_geom)) as c_geom,
		st_collect(rig.s_geom) as s_geom
	FROM 
		yun_intersection_group as rig
	GROUP BY i_id,  i_geom, range_group) as q;

DROP TABLE yun_connection;
CREATE TABLE yun_connection AS
SELECT 
	ST_MakeLine(q1.c_geom, q2.c_geom),
	q1.id as c1_id,
	q2.id as c2_id
FROM 
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id 
	WHERE i.is_t is null and num_s > 3
) as q1,
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id 
	WHERE i.is_t is null and num_s > 3
) as q2,
(
	SELECT i_id, count(range_group)  as count
	FROM yun_corner_group
	GROUP by i_id
) as number
WHERE number.i_id = q1.i_id AND q1.i_id = q2.i_id AND (q1.range_group + 1 = q2.range_group  OR q1.range_group/number.count = q2.range_group);

INSERT INTO yun_connection 
SELECT 
	ST_MakeLine(q1.c_geom, q2.c_geom),
	q1.id as c1_id,
	q2.id as c2_id
FROM 
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id
	WHERE i.is_t and num_s >= 3 AND i.degree_diff[4] != cg.range_group
) as q1,
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id 
	WHERE i.is_t  and num_s >= 3 AND i.degree_diff[4] != cg.range_group
) as q2,
(
	SELECT i_id, count(range_group)  as count
	FROM yun_corner_group
	GROUP by i_id
) as number
WHERE number.i_id = q1.i_id AND q1.i_id = q2.i_id AND (q1.range_group + 1 = q2.range_group  OR q1.range_group/number.count = q2.range_group);

INSERT INTO yun_connection 
SELECT 
	st_shortestline(q1.s_geom,q2.c_geom),
	q1.id as c1_id,
	q2.id as c2_id,
	st_astext(q1.s_geom) 
FROM 
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id
	WHERE i.is_t and num_s >= 3 AND i.degree_diff[4] = cg.range_group
) as q1,
(
	SELECT cg.*, i.degree_diff
	FROM yun_corner_group as cg
	JOIN yun_intersections as i ON i.id = cg.i_id 
	WHERE i.is_t  and num_s >= 3 AND i.degree_diff[4] != cg.range_group
) as q2,
(
	SELECT i_id, count(range_group)  as count
	FROM yun_corner_group
	GROUP by i_id
) as number
WHERE number.i_id = q1.i_id 
	AND q1.i_id = q2.i_id 
	AND (q1.range_group + 1 = q2.range_group 
		OR q1.range_group - 1 = q2.range_group  
		OR q1.range_group/number.count = q2.range_group
		OR q2.range_group/number.count = q1.range_group
		);


