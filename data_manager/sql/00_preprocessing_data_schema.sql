\timing
--
-- Step 0: Create schemas
--
CREATE SCHEMA IF NOT EXISTS source;
CREATE SCHEMA IF NOT EXISTS data;
CREATE SCHEMA IF NOT EXISTS build;

CREATE INDEX streets_index
          ON streets
       USING gist(geom);

CREATE INDEX sidewalks_index
          ON sidewalks
       USING gist(geom);

-- ALTER TABLE curbramps
-- ALTER COLUMN geom TYPE geometry(POINT, 26910)
--        USING ST_Force2D(geom);

CREATE INDEX curbramps_index
          ON curbramps
       USING gist(geom);

--
-- Step 6: Convert SRID to same projection as vector data
--
-- FIXME: ST_Transform from 2926 to 26910 produces gaps in the raster data -
--        some kind of per-tile error at the interface between tiles, I think.
--        This screws up using the DEM because those gaps are null-valued and
--        overlap with sidewalks. This seems like a bug in PostGIS/GDAL/libgeos
-- UPDATE data.ned13
--   SET rast = ST_Transform(rast, 26910);

CREATE INDEX n48w123_convexhull_index
          ON dem.n48w123
       USING gist(ST_ConvexHull(rast));
