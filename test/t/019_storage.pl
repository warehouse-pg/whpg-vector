use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# WarehousePG's default block size is 32K bytes,
# so the dim should be 4 times of 1024 to get 'row is too big' error
my $dim = 4096;

# Initialize node
my $node = PostgreSQL::Test::Cluster->new('node');
$node->init;
$node->start;

# Create table
$node->safe_psql("postgres", "CREATE EXTENSION vector;");
$node->safe_psql("postgres", "CREATE TABLE tst (v1 vector($dim), v2 vector($dim), v3 vector($dim));");

# Test insert succeeds
$node->safe_psql("postgres",
	"INSERT INTO tst SELECT array_agg(n), array_agg(n), array_agg(n) FROM generate_series(1, $dim) n"
);

# Change storage to PLAIN
$node->safe_psql("postgres", "ALTER TABLE tst ALTER COLUMN v1 SET STORAGE PLAIN");
$node->safe_psql("postgres", "ALTER TABLE tst ALTER COLUMN v2 SET STORAGE PLAIN");
$node->safe_psql("postgres", "ALTER TABLE tst ALTER COLUMN v3 SET STORAGE PLAIN");

# Test insert fails
my ($ret, $stdout, $stderr) = $node->psql("postgres",
	"INSERT INTO tst SELECT array_agg(n), array_agg(n), array_agg(n) FROM generate_series(1, $dim) n"
);
like($stderr, qr/row is too big/);

done_testing();
