#ifndef VECTOR_H
#define VECTOR_H

#define VECTOR_MAX_DIM 16000

#define VECTOR_SIZE(_dim)		(offsetof(Vector, x) + sizeof(float)*(_dim))
#define DatumGetVector(x)		((Vector *) PG_DETOAST_DATUM(x))
#define PG_GETARG_VECTOR_P(x)	DatumGetVector(PG_GETARG_DATUM(x))
#define PG_RETURN_VECTOR_P(x)	PG_RETURN_POINTER(x)

typedef struct Vector
{
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	int16		dim;			/* number of dimensions */
	int16		unused;			/* reserved for future use, always zero */
	float		x[FLEXIBLE_ARRAY_MEMBER];
}			Vector;

Vector	   *InitVector(int dim);
void		PrintVector(char *msg, Vector * vector);
int			vector_cmp_internal(Vector * a, Vector * b);

/* TODO Move to better place */
#if PG_VERSION_NUM >= 160000
#define FUNCTION_PREFIX
#else
#define FUNCTION_PREFIX PGDLLEXPORT
#endif

/*
 * Flags for our extension GUCs.
 *
 * WarehousePG forwards a GUC to the segments only if it carries GUC_GPDB_NEED_SYNC flag.
 * In guc_gp.c gpdb_assign_sync_flag defaults all extension GUCs to GUC_GPDB_NO_SYNC
 * if they are not in the exception list (exceptions in sync_guc_name.h).
 * Index scans run on the segments, so ivfflat.probes or hnsw.ef_search without NEED_SYNC would leave
 * them at the boot default on segments, even when they were changed on the coordinator. After a change,
 * the coordinator would report the new value, while the setting silently did nothing.
 */
#ifdef GP_VERSION_NUM
#define PGVECTOR_GUC_FLAGS	GUC_GPDB_NEED_SYNC
#else
#define PGVECTOR_GUC_FLAGS	0
#endif

#endif
