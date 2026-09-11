-- WarehousePG forwards a GUC to the segments only if it carries
-- GUC_GPDB_NEED_SYNC. Without it, ivfflat.probes or
-- hnsw.ef_search leaves every segment at its boot default while the
-- coordinator reports the new value.
--
-- These two checks pass even on unfixed code: a plain SET reaches the
-- segments through CdbDispatchSetCommand, which ignores the flag. Only a
-- cursor-backed scan reads the stale value.
SET optimizer = off;
SET enable_seqscan = off;

CREATE TABLE whpg_guc_sync (id int, val vector(3));
INSERT INTO whpg_guc_sync SELECT i, format('[%s,%s,%s]', i % 97, (i * 7) % 89, (i * 13) % 83)::vector FROM generate_series(1, 997) i;

CREATE INDEX whpg_guc_sync_ivfflat ON whpg_guc_sync USING ivfflat (val vector_l2_ops) WITH (lists = 10);
SET ivfflat.probes = 10;
SELECT count(*) = 997 AS ivfflat_probes_reaches_scan FROM (SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]') s;
DROP INDEX whpg_guc_sync_ivfflat;

CREATE INDEX whpg_guc_sync_hnsw ON whpg_guc_sync USING hnsw (val vector_l2_ops);
SET hnsw.ef_search = 1000;
SELECT count(*) = 997 AS hnsw_ef_search_reaches_scan FROM (SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]') s;
DROP TABLE whpg_guc_sync;

-- Minimal reproducer.
-- Test uses cursor but a cursor is not needed ot hit the bug.
-- The trigger is the portal, and the extended query protocol's Bind step creates one for every ordinary query.
-- So a plain SELECT from a normal driver (e.g. psycopg) is enough.
--
-- Identical data, index and setting to the ivfflat check above, but uses a cursor.
CREATE TABLE whpg_guc_cursor (id int, val vector(3));
INSERT INTO whpg_guc_cursor SELECT i, format('[%s,%s,%s]', i % 97, (i * 7) % 89, (i * 13) % 83)::vector FROM generate_series(1, 997) i;
CREATE INDEX ON whpg_guc_cursor USING ivfflat (val vector_l2_ops) WITH (lists = 10);
-- Counted in plpgsql because a cursor's row count is otherwise only a command
-- tag, which pg_regress suppresses.
CREATE FUNCTION whpg_guc_cursor_rows() RETURNS bigint AS $$
DECLARE
	c CURSOR FOR SELECT id FROM whpg_guc_cursor ORDER BY val <-> '[0,0,0]';
	r record;
	n bigint := 0;
BEGIN
	OPEN c;
	LOOP
		FETCH c INTO r;
		EXIT WHEN NOT FOUND;
		n := n + 1;
	END LOOP;
	CLOSE c;
	RETURN n;
END;
$$ LANGUAGE plpgsql;
SET ivfflat.probes = 10;
SELECT whpg_guc_cursor_rows() = 997 AS ivfflat_probes_reaches_cursor_scan;
DROP FUNCTION whpg_guc_cursor_rows();
DROP TABLE whpg_guc_cursor;
