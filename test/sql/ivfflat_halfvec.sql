SET enable_seqscan = off;

-- L2

CREATE TABLE t (val halfvec(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val halfvec_l2_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <-> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <-> (SELECT NULL::halfvec)) t2;
SELECT COUNT(*) FROM t;

TRUNCATE t;
SELECT * FROM t ORDER BY val <-> '[3,3,3]';

DROP TABLE t;

-- inner product

CREATE TABLE t (val halfvec(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val halfvec_ip_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <#> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <#> (SELECT NULL::halfvec)) t2;

DROP TABLE t;

-- cosine

CREATE TABLE t (val halfvec(3));
INSERT INTO t (val) VALUES ('[0,0,0]'), ('[1,2,3]'), ('[1,1,1]'), (NULL);
CREATE INDEX ON t USING ivfflat (val halfvec_cosine_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES ('[1,2,4]');

SELECT * FROM t ORDER BY val <=> '[3,3,3]';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <=> '[0,0,0]') t2;
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <=> (SELECT NULL::halfvec)) t2;

DROP TABLE t;

-- dimensions

CREATE TABLE t (val halfvec(4000));
CREATE INDEX ON t USING ivfflat (val halfvec_l2_ops);
DROP TABLE t;

CREATE TABLE t (val halfvec(4001));
CREATE INDEX ON t USING ivfflat (val halfvec_l2_ops);
DROP TABLE t;

-- memory

SET maintenance_work_mem = '1MB';
CREATE TABLE t (val halfvec(4000));
CREATE INDEX ON t USING ivfflat (val halfvec_l2_ops);
DROP TABLE t;
RESET maintenance_work_mem;

-- WarehousePG: 0.8.4/0.8.5 made IVFFlat index builds enforce
-- maintenance_work_mem, sizing the sample array from
-- RelationGetNumberOfBlocks() * MaxHeapTuplesPerPage. The same single-row
-- table occupies more heap blocks here than on single-node Postgres, and how
-- many depends on which segment the row lands on, so the memory the build
-- needs is both higher than upstream's tight limit and not constant
-- (observed 10-13 MB where upstream needs under 5). Give it headroom: this
-- block asserts the build succeeds, while the 1MB block above still covers
-- the enforcement path itself.
SET maintenance_work_mem = '32MB';
CREATE TABLE t (val halfvec(4000));
INSERT INTO t (val) VALUES (array_fill(0, ARRAY[4000]));
CREATE INDEX ON t USING ivfflat (val halfvec_l2_ops);
DROP TABLE t;
RESET maintenance_work_mem;
