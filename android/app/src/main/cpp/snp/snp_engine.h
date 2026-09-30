#ifndef GENE_SNP_ENGINE_H
#define GENE_SNP_ENGINE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint64_t total, ref, alt, ambiguous, coverage_only, skipped_buckets;
} snp_counts;
typedef int (*snp_cancel_fn)(void *context);
enum {
    SNP_OK=0, SNP_INVALID_QUERY, SNP_INVALID_FORMAT, SNP_NOT_SEEKABLE,
    SNP_IO_ERROR, SNP_RESOURCE_LIMIT, SNP_CANCELLED
};
/* Borrowed descriptors; never closed or written by this function. */
int snp_query(int idxfd,int idsfd,const char *sequence,char ref,char alt,
              snp_counts *out,snp_cancel_fn cancelled,void *context);
const char *snp_error_code(int error);
#ifdef __cplusplus
}
#endif
#endif
