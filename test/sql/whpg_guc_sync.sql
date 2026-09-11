-- New segment processes only get GUCs marked GUC_GPDB_NEED_SYNC. Cursors and
-- extended-protocol queries use new segment processes, so ivfflat.probes and
-- hnsw.ef_search need the flag to reach the index scan. Without it the
-- segments scan with the boot default while the coordinator reports the new
-- value.
--
-- The plain SELECT checks pass even without the flag: a plain SET is sent to
-- the existing segment processes regardless. Only the cursor checks reproduce
-- the bug. A cursor is not needed to hit it in practice: an ordinary query
-- from a driver using the extended protocol (e.g. psycopg) is enough.
SET optimizer = off;
SET enable_seqscan = off;
-- Both settings come before any cursor runs. A SET also reaches idle cached
-- segment processes, so a later cursor reusing one would see the value even
-- without the flag.
SET ivfflat.probes = 10;
SET hnsw.ef_search = 1000;

CREATE TABLE whpg_guc_sync (id int, val vector(3));
INSERT INTO whpg_guc_sync SELECT i, format('[%s,%s,%s]', i % 97, (i * 7) % 89, (i * 13) % 83)::vector FROM generate_series(1, 997) i;

-- Counted in plpgsql because a cursor's row count is otherwise only a command
-- tag, which pg_regress suppresses.
CREATE FUNCTION whpg_guc_cursor_rows(q text) RETURNS bigint AS $$
DECLARE
	c refcursor;
	r record;
	n bigint := 0;
BEGIN
	OPEN c FOR EXECUTE q;
	LOOP
		FETCH c INTO r;
		EXIT WHEN NOT FOUND;
		n := n + 1;
	END LOOP;
	CLOSE c;
	RETURN n;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX whpg_guc_sync_ivfflat ON whpg_guc_sync USING ivfflat (val vector_l2_ops) WITH (lists = 10);
SELECT count(*) = 997 AS ivfflat_probes_reaches_scan FROM (SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]') s;
SELECT whpg_guc_cursor_rows($q$SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]'$q$) = 997 AS ivfflat_probes_reaches_cursor_scan;
DROP INDEX whpg_guc_sync_ivfflat;

CREATE INDEX whpg_guc_sync_hnsw ON whpg_guc_sync USING hnsw (val vector_l2_ops);
SELECT count(*) = 997 AS hnsw_ef_search_reaches_scan FROM (SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]') s;
SELECT whpg_guc_cursor_rows($q$SELECT id FROM whpg_guc_sync ORDER BY val <-> '[0,0,0]'$q$) = 997 AS hnsw_ef_search_reaches_cursor_scan;

DROP FUNCTION whpg_guc_cursor_rows(text);
DROP TABLE whpg_guc_sync;
