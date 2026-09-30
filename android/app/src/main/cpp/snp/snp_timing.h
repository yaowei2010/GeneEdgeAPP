#ifndef GENE_SNP_TIMING_H
#define GENE_SNP_TIMING_H
#include "snp_engine.h"
typedef struct { double io_ms, count_ms, genotype_ms, overhead_ms, total_ms; } snp_stage_timing;
/* Integer nanoseconds prevent rounding from being counted as another stage. */
static inline int snp_split_timing(uint64_t query, uint64_t io, uint64_t genotype,
                                  uint64_t total, snp_stage_timing *out) {
    if (!out || io > query || query > total || genotype > total-query) return SNP_IO_ERROR;
    out->io_ms=(double)io/1e6; out->count_ms=(double)(query-io)/1e6;
    out->genotype_ms=(double)genotype/1e6;
    out->overhead_ms=(double)(total-query-genotype)/1e6; out->total_ms=(double)total/1e6;
    return SNP_OK;
}
#endif
