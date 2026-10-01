#ifndef GENE_LOCUS_GENOTYPE_MODEL_H
#define GENE_LOCUS_GENOTYPE_MODEL_H
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
enum { LOCUS_GENOTYPE_OK=0,LOCUS_GENOTYPE_INVALID_CONFIG,
       LOCUS_GENOTYPE_INVALID_COUNTS,LOCUS_GENOTYPE_NUMERIC_ERROR };
typedef struct {
    double epsilon,rho,priors[10];
    uint64_t min_depth;
    double min_posterior;
} locus_genotype_config;
/* Counts and genotype indices use A,C,G,T. Posterior enumeration i<=j. */
typedef struct {
    double posterior[10],best_posterior,log_score_gap;
    uint64_t effective_depth;
    int best_i,best_j;
    bool called,calibrated;
    const char *no_call_reason,*model_version;
} locus_genotype_result;
locus_genotype_config locus_genotype_default_config(void);
int locus_genotype_call(const uint64_t counts[4],const locus_genotype_config *config,
                         locus_genotype_result *result);
#ifdef __cplusplus
}
#endif
#endif
