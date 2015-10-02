-- Step 0: Create index on compkey
CREATE UNIQUE INDEX street_compkey ON street (compkey);
--- However, postgresql does not allow me to this because compkey is not unique. Find compkey that is not unique

 -- street with compkey includes same geom information. I remove all the repetition.
DELETE FROM street
WHERE id IN (
SELECT id
FROM (SELECT id,ROW_NUMBER() OVER (partition BY compkey ORDER BY id) AS rnum FROM street) as t
WHERE t.rnum > 1);
-- Now we can create index
CREATE UNIQUE INDEX street_compkey ON street (compkey);

-- Step 1: Polygonizing
CREATE TABLE boundary_polygons AS
SELECT g.path[1] as gid,geom
FROM(
	SELECT (ST_Dump(ST_Polygonize(picked_sidewalks.geom))).*
	FROM (
		SELECT DISTINCT ON (s.id) s.id, s.geom
		FROM street s
		LEFT JOIN raw_sidewalks r ON s.compkey = r.segkey
		WHERE r.id is not null) as picked_sidewalks
	) as g;

-- Step 2: Remove overlap polygons
DELETE FROM boundary_polygons
WHERE gid in (
SELECT b1.gid FROM boundary_polygons b1, boundary_polygons b2
WHERE ST_Overlaps(b1.geom, b2.geom)
GROUP BY b1.gid HAVING count(b1.gid) > 1);

--- Step1: Find all sidewalks what are within a polygons
CREATE TABLE grouped_sidewalks AS
SELECT b.gid as b_id, s.id as s_id, s.geom as s_geom
FROM processed_sidewalks as s
LEFT JOIN boundary_polygons  as b ON ST_Within(s.geom,b.geom);
-- 39609 sidewalks are classified in this step.

---  Step2: Find all polygons that is not assigned to any polygons because of offshoots.
UPDATE grouped_sidewalks
SET b_id = query.b_id
FROM(
SELECT b.gid as b_id, s.s_id, s.s_geom as s_geom FROM
(SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN boundary_polygons as b ON ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5),b.geom) = True) AS query
WHERE grouped_sidewalks.s_id = query.s_id;

-- highway

--- Not important: For qgis visualization
CREATE VIEW correct_sidewalks AS
SELECT b.id as b_id, s.s_id,ST_MakeLine(ST_Line_Interpolate_Point(s.sidewalk_geom, 0.5),ST_Centroid(b.geom)) as geom FROM
(SELECT * FROM polygon_sidewalks
WHERE b_id is null) as s
INNER JOIN boundaryPolygons as b ON ST_Intersects(s.sidewalk_geom, b.geom)
WHERE ST_Within(ST_Line_Interpolate_Point(s.sidewalk_geom, 0.5),b.geom) = True;

--- Find a bad polygon(id:666) which looks like a highway.
-- There are 57 Polygons that has centroid outside the polygon. Most of them works well with our algorithm.
CREATE VIEW bad_polygons AS
SELECT * from boundarypolygons as b
WHERE  ST_Within(ST_Centroid(b.geom), b.geom) = False;


-- Step 3: Boundaries
-- There are 2779 sidewalks has not been assigned to any polygons

CREATE VIEW union_polygons AS
SELECT q.path[1] as id,geom
FROM (select (st_dump(st_union(geom))).* from boundary_polygons) AS q

-- For each unAssigned it to the closest polygons
UPDATE grouped_sidewalks
SET b_id = query.b_id
FROM (
SELECT DISTINCT ON (s.s_id) s.s_id as s_id, u.id as b_id
FROM (SELECT * FROM grouped_sidewalks
WHERE b_id is null) as s
INNER JOIN union_polygons  as u
ORDER BY s.s_id, ST_Distance(s.s_geom, u.geom)  ) AS query
WHERE grouped_sidewalks.s_id = query.s_id
