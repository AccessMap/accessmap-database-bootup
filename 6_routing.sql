-- DROP FUNCTION pgr_dijkstra(varchar, int, int, varchar);

CREATE OR REPLACE FUNCTION accessmap_pgr_dijkstra(
                IN tbl varchar,
                IN source integer,
                IN target integer,
                IN cost_function varchar,
                OUT seq integer,
                OUT id integer,
                OUT geom geometry
        )
        RETURNS SETOF record AS
$BODY$
DECLARE
        sql     text;
        rec     record;
BEGIN
        seq     := 0;
        sql     := 'SELECT id,geom FROM ' ||
                        'pgr_dijkstra(''SELECT id as id, source::int, target::int, '
                                        || cost_function || ' AS cost FROM '
                                        || quote_ident(tbl) || ''', '
                                        || quote_literal(source) || ', '
                                        || quote_literal(target) || ' , false, false), '
                                || quote_ident(tbl) || ' WHERE id2 = id ORDER BY seq';

        FOR rec IN EXECUTE sql
        LOOP
                seq     := seq + 1;
                id     := rec.id;
                geom    := rec.geom;
                RETURN NEXT;
        END LOOP;
        RETURN;
END;
$BODY$
LANGUAGE 'plpgsql' VOLATILE STRICT;
---Example:
SELECT pgr_fromAtoB('sidewalks_ready_routing', -122.315366,47.661083,-122.313333,47.659325,'ST_length(geom)');


--
--DROP FUNCTION pgr_fromAtoB(varchar, double precision, double precision,
--                           double precision, double precision);

CREATE OR REPLACE FUNCTION pgr_points(
                IN tbl varchar,
                IN x1 double precision,
                IN y1 double precision,
                IN x2 double precision,
                IN y2 double precision,
                IN cost_function varchar
        )
        RETURNS SETOF record AS
$BODY$
DECLARE
        sql     text;
        rec     record;
        source  integer;
        target  integer;
        point   integer;
        tbl_name text;

BEGIN
        -- Find nearest node
        tbl_name = ''|| tbl || '_vertices_pgr';
        EXECUTE 'SELECT id::integer FROM '||quote_ident(tbl_name)||'
                        ORDER BY st_distance(the_geom,st_transform(ST_GeomFromText(''POINT('
                        || x1 || ' ' || y1 || ')'',4326),2926)) LIMIT 1' INTO rec;
        source := rec.id;

        EXECUTE 'SELECT id::integer FROM '||quote_ident(tbl_name)||'
                        ORDER BY st_distance(the_geom,st_transform(ST_GeomFromText(''POINT('
                        || x2 || ' ' || y2 || ')'',4326),2926)) LIMIT 1' INTO rec;
        target := rec.id;
        RETURN source;
END;
$BODY$
LANGUAGE 'plpgsql' VOLATILE STRICT;


CREATE OR REPLACE FUNCTION pgr_fromAtoB(
                IN tbl varchar,
                IN x1 double precision,
                IN y1 double precision,
                IN x2 double precision,
                IN y2 double precision,
                IN cost_function varchar,
                OUT seq integer,
                OUT id integer,
                OUT name text,
                OUT heading double precision,
                OUT cost double precision,
                OUT geom geometry
        )
        RETURNS SETOF record AS
$BODY$
DECLARE
        sql     text;
        rec     record;
        source	integer;
        target	integer;
        point	integer;
        tbl_name text;

BEGIN
	-- Find nearest node
        tbl_name = ''|| tbl || '_vertices_pgr';
        EXECUTE 'SELECT id::integer FROM '||quote_ident(tbl_name)||'
                        ORDER BY st_distance(the_geom,st_transform(ST_GeomFromText(''POINT('
                        || x1 || ' ' || y1 || ')'',4326),2926)) LIMIT 1' INTO rec;
        source := rec.id;

        EXECUTE 'SELECT id::integer FROM '||quote_ident(tbl_name)||'
                        ORDER BY st_distance(the_geom,st_transform(ST_GeomFromText(''POINT('
                        || x2 || ' ' || y2 || ')'',4326),2926)) LIMIT 1' INTO rec;
        target := rec.id;

	-- Shortest path query (TODO: limit extent by BBOX)
        seq := 0;
        sql := 'SELECT id, geom, cost, source, target,
				ST_Reverse(geom) AS flip_geom FROM ' ||
                        'pgr_dijkstra(''SELECT id as id, source::int, target::int, '
                                        || cost_function || ' AS cost FROM '
                                        || quote_ident(tbl) || ''', '
                                        || source || ', ' || target
                                        || ' , false, false), '
                                || quote_ident(tbl) || ' WHERE id2 = id ORDER BY seq';

	-- Remember start point
        point := source;
        FOR rec IN EXECUTE sql
        LOOP
		-- Flip geometry (if required)
		IF ( point != rec.source ) THEN
			rec.geom := rec.flip_geom;
			point := rec.source;
		ELSE
			point := rec.target;
		END IF;

		-- Calculate heading (simplified)
		EXECUTE 'SELECT degrees( ST_Azimuth(
				ST_StartPoint(''' || rec.geom::text || '''),
				ST_EndPoint(''' || rec.geom::text || ''') ) )'
			INTO heading;

		-- Return record
                seq     := seq + 1;
                id     := rec.id;
                name    := rec.name;
                cost    := rec.cost;
                geom    := ST_astext(rec.geom);
                RETURN NEXT;
        END LOOP;
        RETURN;
END;
$BODY$
LANGUAGE 'plpgsql' VOLATILE STRICT;
