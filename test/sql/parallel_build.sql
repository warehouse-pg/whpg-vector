-- Parallel index builds after the session has opened a cursor.
--
-- A cursor (DECLARE CURSOR, or the implicit cursor of a PL/pgSQL FOR loop)
-- makes the coordinator tell the writer QEs to publish their snapshot, and
-- every parallel worker those QEs launch afterwards restores that state.
-- The parallel_workers reloption forces workers on every segment and on the
-- coordinator regardless of table size, so the small table here still runs
-- the parallel build path.

CREATE TABLE pb_ctl (id int, loaded bool) DISTRIBUTED BY (id);
INSERT INTO pb_ctl SELECT g, false FROM generate_series(1, 3) g;

CREATE TABLE pb_heap (id int, val vector(3)) WITH (parallel_workers = 2) DISTRIBUTED BY (id);
INSERT INTO pb_heap SELECT g, ARRAY[g % 7, g % 11, g % 13]::vector FROM generate_series(1, 600) g;

-- Build the index inside a PL/pgSQL loop over a query, the shape of an
-- ingest function that indexes one partition per iteration.
CREATE FUNCTION pb_ingest(p_index_type text) RETURNS void AS $$
DECLARE
    rec record;
BEGIN
    FOR rec IN SELECT id FROM pb_ctl WHERE NOT loaded ORDER BY id LIMIT 1 LOOP
        IF p_index_type = 'ivfflat' THEN
            EXECUTE 'CREATE INDEX pb_heap_ivfflat_idx ON pb_heap USING ivfflat (val vector_l2_ops) WITH (lists = 3)';
        ELSE
            EXECUTE 'CREATE INDEX pb_heap_hnsw_idx ON pb_heap USING hnsw (val vector_l2_ops)';
        END IF;
        UPDATE pb_ctl SET loaded = true WHERE id = rec.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

BEGIN;
SELECT pb_ingest('ivfflat');
COMMIT;

BEGIN;
SELECT pb_ingest('hnsw');
COMMIT;

-- The same with an explicit cursor.
BEGIN;
DECLARE pb_cur CURSOR FOR SELECT id FROM pb_ctl ORDER BY id;
FETCH 1 FROM pb_cur;
CREATE INDEX pb_heap_ivfflat_idx2 ON pb_heap USING ivfflat (val vector_l2_ops) WITH (lists = 3);
CLOSE pb_cur;
COMMIT;

-- The session still works and the indexes are usable.
SELECT count(*) FROM pb_ctl WHERE loaded;
SET enable_seqscan = off;
SELECT count(*) FROM (SELECT id FROM pb_heap ORDER BY val <-> '[1,2,3]' LIMIT 5) t;
RESET enable_seqscan;
SELECT indexname FROM pg_indexes WHERE tablename = 'pb_heap' ORDER BY indexname;

-- Without the reloption, workers are planned from the table size on each
-- segment (min_parallel_table_scan_size is a per-segment setting), so load
-- 45000 rows per primary: about 13MB per segment whatever the segment count,
-- well above the default 8MB threshold.  The coordinator's copy of the table
-- is empty and builds serially, so only the segments launch workers.  The
-- INSERT runs in a DO block because its row count depends on the cluster.
CREATE TABLE pb_big (id int, val vector(64)) DISTRIBUTED BY (id);
DO $$
BEGIN
    INSERT INTO pb_big
    SELECT g, (SELECT array_agg((g * k) % 97) FROM generate_series(1, 64) k)::vector(64)
    FROM generate_series(1, 45000 * (SELECT count(*)::int FROM gp_segment_configuration
                                      WHERE role = 'p' AND content >= 0)) g;
END
$$;
SELECT min(sz) > 8 * 1024 * 1024 AS every_segment_above_threshold
FROM (SELECT pg_relation_size('pb_big') AS sz FROM gp_dist_random('gp_id')) s;

BEGIN;
DECLARE pb_cur CURSOR FOR SELECT id FROM pb_ctl ORDER BY id;
FETCH 1 FROM pb_cur;
CREATE INDEX pb_big_ivfflat_idx ON pb_big USING ivfflat (val vector_l2_ops) WITH (lists = 10);
CLOSE pb_cur;
COMMIT;

SET enable_seqscan = off;
SELECT count(*) FROM (SELECT id FROM pb_big ORDER BY val <-> (SELECT val FROM pb_big WHERE id = 1) LIMIT 5) t;
RESET enable_seqscan;

DROP FUNCTION pb_ingest(text);
DROP TABLE pb_big;
DROP TABLE pb_heap;
DROP TABLE pb_ctl;
