Generalized workflow:
Inputs:
  'streets' table with these columns:
  'sidewalks' table with these columns:
  'ned13' table of imported NED 1/3 arc second data

Big FIXMEs:
  * curbs get annotated in step 6 from sidewalks (practical for Seattle, but not other cities),
    should instead be an input table generated from preprocessing.

Key ideas:
  * Keep everything in a single projection system as long as possible. Because
    we're not experts at knowing which one to use yet, stick to WGS84 as much
    as possible so we can use lat/lon.

1. Preprocessing for Seattle data to get it into standardized formats
2. Processing input data to ensure standardized formats and views
  a. Streets: make unique id column, geom column,
    * Ensure geom is LineString with ST_LineMerge(geom)
      * This is not the long-term desired behavior - should instead split
        into one row per LineString in each MultiLineString

