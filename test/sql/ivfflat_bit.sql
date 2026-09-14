SET enable_seqscan = off;

-- hamming

CREATE TABLE t (val bit(3));
INSERT INTO t (val) VALUES (B'000'), (B'100'), (B'111'), (NULL);
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops) WITH (lists = 1);

INSERT INTO t (val) VALUES (B'110');

SELECT * FROM t ORDER BY val <~> B'111';
SELECT COUNT(*) FROM (SELECT * FROM t ORDER BY val <~> (SELECT NULL::bit)) t2;

DROP TABLE t;

-- varbit

CREATE TABLE t (val varbit(3));
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops) WITH (lists = 1);
CREATE INDEX ON t USING ivfflat ((val::bit(3)) bit_hamming_ops) WITH (lists = 1);
CREATE INDEX ON t USING ivfflat ((val::bit(64001)) bit_hamming_ops) WITH (lists = 1);
CREATE INDEX ON t USING ivfflat ((val::bit(2)) bit_hamming_ops) WITH (lists = 5);
DROP TABLE t;

-- dimensions

CREATE TABLE t (val bit(64000));
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops);
DROP TABLE t;

CREATE TABLE t (val bit(64001));
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops);
DROP TABLE t;

-- memory

SET maintenance_work_mem = '1MB';
CREATE TABLE t (val bit(64000));
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops);
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
SET maintenance_work_mem = '96MB';
CREATE TABLE t (val bit(64000));
INSERT INTO t (val) VALUES (B'0'::bit(64000));
CREATE INDEX ON t USING ivfflat (val bit_hamming_ops);
DROP TABLE t;
RESET maintenance_work_mem;
