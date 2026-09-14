SET enable_seqscan = off;

-- L2

CREATE TABLE t (val vector(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val vector_l2_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <-> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <-> (SELECT NULL::vector)) t2;
SELECT COUNT(*) FROM t;

TRUNCATE t;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

DROP TABLE t;

-- inner product

CREATE TABLE t (val vector(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val vector_ip_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <#> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <#> (SELECT NULL::vector)) t2;

DROP TABLE t;

-- cosine

CREATE TABLE t (val vector(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val vector_cosine_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <=> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <=> '[0,0,0]') t2;
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <=> (SELECT NULL::vector)) t2;

DROP TABLE t;

-- iterative

-- WarehousePG: ivfflat.max_probes caps probes per segment, so under a probe
-- limit the reachable rows depend on which segment holds them. A vector-only
-- table has no column suitable as a hash distribution key, so placement is
-- non-deterministic and the probe-limited results below would be flaky.
-- Replicate the data and read it from one segment to match single-node
-- semantics deterministically.
CREATE TABLE t (val vector(3)) DISTRIBUTED REPLICATED;
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val vector_l2_ops) WITH (lists = 3);
SET enable_seqscan = off;

SET ivfflat.iterative_scan = relaxed_order;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

SET ivfflat.max_probes = 1;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

SET ivfflat.max_probes = 2;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

TRUNCATE t;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

RESET ivfflat.iterative_scan;
RESET ivfflat.max_probes;
RESET enable_seqscan;
DROP TABLE t;

-- unlogged

-- WarehousePG: with only 4 rows spread over N segments, the 0.8.x ivfflat
-- cost estimate lands close enough to a seq scan that the chosen plan flips
-- with row placement, which is non-deterministic for a vector-only table
-- (no column is suitable as a hash distribution key). Force the index scan
-- so this exercises the unlogged-table path rather than the planner.
CREATE UNLOGGED TABLE t (val vector(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val vector_l2_ops) WITH (lists = 1);
SET enable_seqscan = off;

SELECT * FROM t ORDER BY val <-> '[3,3,3]';

RESET enable_seqscan;
DROP TABLE t;

-- options

CREATE TABLE t (val vector(3));
CREATE INDEX ON t USING ivfflat (val vector_l2_ops) WITH (lists = 0);
CREATE INDEX ON t USING ivfflat (val vector_l2_ops) WITH (lists = 32769);

SHOW ivfflat.probes;

SET ivfflat.probes = 0;
SET ivfflat.probes = 32769;

SHOW ivfflat.iterative_scan;

SET ivfflat.iterative_scan = on;

SHOW ivfflat.max_probes;

SET ivfflat.max_probes = 0;
SET ivfflat.max_probes = 32769;

DROP TABLE t;
