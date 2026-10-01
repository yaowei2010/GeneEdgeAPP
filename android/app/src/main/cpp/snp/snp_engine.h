#ifndef GENE_SNP_ENGINE_H
#define GENE_SNP_ENGINE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint64_t total, ref, alt, ambiguous, coverage_only, skipped_buckets;
} snp_counts;
typedef int (*snp_cancel_fn)(void *context);
typedef struct { uint64_t io_ns, query_ns; int clock_failed; } snp_timing;
/* bases always ordered A,C,G,T; each read contributes to only one category. */
typedef struct {
    uint64_t total, bases[4], ambiguous, coverage_only, skipped_buckets;
} snp_locus_counts;
int snp_locus_validate(const char *const *sequences,const char *refs,size_t count);
int snp_locus_query(int idxfd,int idsfd,const char *sequence,
                    snp_locus_counts *out,snp_cancel_fn cancelled,void *context,
                    snp_timing *timing);
enum {
    SNP_OK=0, SNP_INVALID_QUERY, SNP_INVALID_FORMAT, SNP_NOT_SEEKABLE,
    SNP_IO_ERROR, SNP_RESOURCE_LIMIT, SNP_CANCELLED
};
/* Borrowed descriptors; never closed or written by this function. */
int snp_query(int idxfd,int idsfd,const char *sequence,char ref,char alt,
              snp_counts *out,snp_cancel_fn cancelled,void *context);
const char *snp_error_code(int error);
/* Optional instrumentation; NULL skips per-I/O clock reads. */
int snp_query_timed(int idxfd,int idsfd,const char *sequence,char ref,char alt,
                    snp_counts *out,snp_cancel_fn cancelled,void *context,snp_timing *timing);
#ifdef __cplusplus
}
#endif
#endif
