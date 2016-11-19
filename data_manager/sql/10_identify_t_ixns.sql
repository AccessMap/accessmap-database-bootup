-- TODO: refactor to remove redundant intermediate steps
-----------------------------------------------------------------------------
-- Step 1: Function to find the largest angle between streets in intersection
-----------------------------------------------------------------------------
-- Note: The difference of the max_degree and min_degree IS calculated after
--       mod 2 * pi.

CREATE OR REPLACE FUNCTION Find_Maximum_Degree_Diff(a_degree double precision[], count bigint)
RETURNS double precision[] AS
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

          ALTER TABLE build.intersections
DROP COLUMN IF EXISTS degree_diff;

ALTER TABLE build.intersections
 ADD COLUMN degree_diff double precision[];

UPDATE build.intersections
   SET degree_diff = Find_Maximum_Degree_Diff(degree, num_s);

          ALTER TABLE build.intersections
DROP COLUMN IF EXISTS is_t;

ALTER TABLE build.intersections
 ADD COLUMN is_t boolean DEFAULT FALSE;

UPDATE build.intersections
   SET is_t = TRUE
 WHERE num_s >= 3
   AND degrees(degree_diff[3]) > 170
   AND degrees(degree_diff[3]) < 190;
