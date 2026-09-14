-- WarehousePG MPP coverage.
--
-- Upstream pgvector has no MPP: it tests everything on single-node heap tables,
-- so none of the behaviour below is covered upstream. This exercises index
-- build, insert, scan and vacuum on tables DISTRIBUTED across segments, for
-- every type that has an index opclass (vector, halfvec, sparsevec, bit) on
-- both index AMs.
--
-- Determinism: every table declares an explicit DISTRIBUTED BY (id), so
-- placement is a deterministic hash of a fixed integer key. A vector-typed
-- column cannot serve as a distribution key, so a table declared without
-- DISTRIBUTED BY gets a random policy and per-segment behaviour becomes
-- irreproducible -- which is exactly what makes the upstream ivfflat iterative
-- and unlogged tests flaky here. enable_seqscan is off throughout so the index
-- paths are actually exercised rather than optimised away on small inputs.

SET enable_seqscan = off;
-- ivfflat is approximate: with lists = 2 the default probes = 1 scans half the
-- lists per segment, so which rows surface depends on how the distribution key
-- spread them. Probe every list so these assertions test correctness rather
-- than recall. hnsw.ef_search defaults to 40, already well above the LIMITs here.
SET ivfflat.probes = 2;

CREATE TABLE mpp (
	id int,
	v  vector(3),
	h  halfvec(3),
	s  sparsevec(3),
	b  bit(9)
) DISTRIBUTED BY (id);

INSERT INTO mpp
SELECT g,
	('[' || g || ',' || (g % 7) || ',' || (g % 5) || ']')::vector(3),
	('[' || g || ',' || (g % 7) || ',' || (g % 5) || ']')::halfvec(3),
	('{1:' || g || ',2:' || (g % 7) || '}/3')::sparsevec,
	(g % 512)::bit(9)
FROM generate_series(1, 60) g;

-- the data really is spread over more than one segment
SELECT count(DISTINCT gp_segment_id) > 1 AS multi_segment, count(*) AS rows FROM mpp;

-- how many segments actually hold rows
SELECT count(DISTINCT gp_segment_id) AS segments_with_rows FROM mpp;

-- index build on a distributed table, one index per type/AM/opclass
CREATE INDEX mpp_hnsw_v ON mpp USING hnsw (v vector_l2_ops);
CREATE INDEX mpp_hnsw_h ON mpp USING hnsw (h halfvec_l2_ops);
CREATE INDEX mpp_hnsw_s ON mpp USING hnsw (s sparsevec_l2_ops);
CREATE INDEX mpp_hnsw_b ON mpp USING hnsw (b bit_hamming_ops);
CREATE INDEX mpp_hnsw_bj ON mpp USING hnsw (b bit_jaccard_ops);
CREATE INDEX mpp_ivf_v ON mpp USING ivfflat (v vector_l2_ops) WITH (lists = 2);
CREATE INDEX mpp_ivf_h ON mpp USING ivfflat (h halfvec_l2_ops) WITH (lists = 2);
CREATE INDEX mpp_ivf_b ON mpp USING ivfflat (b bit_hamming_ops) WITH (lists = 2);
-- ivfflat has no sparsevec opclass; confirm that is still true
SELECT count(*) AS ivfflat_sparsevec_opclasses
FROM pg_opclass o JOIN pg_am a ON a.oid = o.opcmethod JOIN pg_type t ON t.oid = o.opcintype
WHERE a.amname = 'ivfflat' AND t.typname = 'sparsevec';

-- indexes are valid on every segment, not just the coordinator
SELECT count(*) AS invalid_indexes FROM gp_dist_random('pg_index') i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relname LIKE 'mpp_%' AND NOT i.indisvalid;

-- scan: vector / halfvec / sparsevec have distinct distances, so ids are stable
SELECT id FROM mpp ORDER BY v <-> '[0,0,0]' LIMIT 3;
SELECT id FROM mpp ORDER BY h <-> '[0,0,0]' LIMIT 3;
SELECT id FROM mpp ORDER BY s <-> '{}/3' LIMIT 3;
-- bit distances tie, so assert on the distances themselves
SELECT (b <~> '000000000') AS hamming FROM mpp ORDER BY 1 LIMIT 3;
SELECT round((b <%> '000000001')::numeric, 4) AS jaccard FROM mpp ORDER BY 1 LIMIT 3;

-- insert path: rows added after the indexes exist
INSERT INTO mpp
SELECT g,
	('[' || g || ',' || (g % 7) || ',' || (g % 5) || ']')::vector(3),
	('[' || g || ',' || (g % 7) || ',' || (g % 5) || ']')::halfvec(3),
	('{1:' || g || ',2:' || (g % 7) || '}/3')::sparsevec,
	(g % 512)::bit(9)
FROM generate_series(61, 80) g;

SELECT count(*) AS rows_after_insert FROM mpp;
SELECT id FROM mpp ORDER BY v <-> '[100,0,0]' LIMIT 3;
SELECT id FROM mpp ORDER BY s <-> '{1:100}/3' LIMIT 3;

-- vacuum path: delete then VACUUM, which dispatches bulkdelete to each segment
DELETE FROM mpp WHERE id % 3 = 0;
VACUUM mpp;

SELECT count(*) AS rows_after_vacuum FROM mpp;
-- deleted ids must not come back through any index
SELECT count(*) AS deleted_still_indexed FROM (SELECT id FROM mpp ORDER BY v <-> '[0,0,0]' LIMIT 20) q WHERE id % 3 = 0;
SELECT id FROM mpp ORDER BY v <-> '[0,0,0]' LIMIT 3;
SELECT id FROM mpp ORDER BY h <-> '[0,0,0]' LIMIT 3;
SELECT id FROM mpp ORDER BY s <-> '{}/3' LIMIT 3;
SELECT (b <~> '000000000') AS hamming FROM mpp ORDER BY 1 LIMIT 3;

VACUUM ANALYZE mpp;
SELECT id FROM mpp ORDER BY v <-> '[0,0,0]' LIMIT 3;

-- iterative scan (new in 0.8.0) on a distributed table, both AMs.
-- max_probes / ef_search apply per segment, so assert on row counts rather
-- than on which rows a probe limit happens to reach.
SET hnsw.iterative_scan = relaxed_order;
SET hnsw.ef_search = 1;
SELECT count(*) AS hnsw_relaxed FROM (SELECT id FROM mpp ORDER BY v <-> '[0,0,0]') q;
SET hnsw.iterative_scan = strict_order;
SELECT count(*) AS hnsw_strict FROM (SELECT id FROM mpp ORDER BY v <-> '[0,0,0]') q;
RESET hnsw.iterative_scan;
RESET hnsw.ef_search;

SET ivfflat.iterative_scan = relaxed_order;
SELECT count(*) AS ivfflat_relaxed FROM (SELECT id FROM mpp ORDER BY v <-> '[0,0,0]') q;
RESET ivfflat.iterative_scan;

DROP TABLE mpp;

-- distribution policy variants: build and scan under each policy
CREATE TABLE mpp_rand (id int, v vector(3)) DISTRIBUTED RANDOMLY;
INSERT INTO mpp_rand SELECT g, ('[' || g || ',0,0]')::vector(3) FROM generate_series(1, 40) g;
CREATE INDEX ON mpp_rand USING hnsw (v vector_l2_ops);
CREATE INDEX ON mpp_rand USING ivfflat (v vector_l2_ops) WITH (lists = 2);
INSERT INTO mpp_rand SELECT g, ('[' || g || ',0,0]')::vector(3) FROM generate_series(41, 50) g;
DELETE FROM mpp_rand WHERE id % 5 = 0;
VACUUM mpp_rand;
SELECT count(*) AS rand_rows FROM mpp_rand;
SELECT id FROM mpp_rand ORDER BY v <-> '[0,0,0]' LIMIT 3;
DROP TABLE mpp_rand;

CREATE TABLE mpp_repl (id int, v vector(3)) DISTRIBUTED REPLICATED;
INSERT INTO mpp_repl SELECT g, ('[' || g || ',0,0]')::vector(3) FROM generate_series(1, 40) g;
CREATE INDEX ON mpp_repl USING hnsw (v vector_l2_ops);
CREATE INDEX ON mpp_repl USING ivfflat (v vector_l2_ops) WITH (lists = 2);
INSERT INTO mpp_repl SELECT g, ('[' || g || ',0,0]')::vector(3) FROM generate_series(41, 50) g;
DELETE FROM mpp_repl WHERE id % 5 = 0;
VACUUM mpp_repl;
SELECT count(*) AS repl_rows FROM mpp_repl;
SELECT id FROM mpp_repl ORDER BY v <-> '[0,0,0]' LIMIT 3;
DROP TABLE mpp_repl;

-- append-optimized storage: the fork explicitly disables parallel index builds
-- for AO tables (RelationIsAppendOptimized in hnswbuild.c / ivfbuild.c)
CREATE TABLE mpp_ao (id int, v vector(3)) WITH (appendonly = true) DISTRIBUTED BY (id);
INSERT INTO mpp_ao SELECT g, ('[' || g || ',0,0]')::vector(3) FROM generate_series(1, 40) g;
CREATE INDEX ON mpp_ao USING hnsw (v vector_l2_ops);
CREATE INDEX ON mpp_ao USING ivfflat (v vector_l2_ops) WITH (lists = 2);
SELECT count(*) AS ao_rows FROM mpp_ao;
SELECT id FROM mpp_ao ORDER BY v <-> '[0,0,0]' LIMIT 3;
DROP TABLE mpp_ao;

RESET ivfflat.probes;
RESET enable_seqscan;
