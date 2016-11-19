--
-- convert to latlon
--

-- sidewalks
ALTER TABLE sidewalks
ALTER COLUMN geom
        TYPE geometry(LINESTRING, 4326)
       USING ST_Transform(geom, 4326);

-- crossings
ALTER TABLE crossings
ALTER COLUMN geom
        TYPE geometry(LINESTRING, 4326)
       USING ST_Transform(geom, 4326);

-- curbramps
ALTER TABLE curbramps
ALTER COLUMN geom
        TYPE geometry(POINT, 4326)
       USING ST_Transform(geom, 4326);
