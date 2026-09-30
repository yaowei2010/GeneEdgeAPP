#ifndef GENEAPP_GENOTYPE_MODEL_H
#define GENEAPP_GENOTYPE_MODEL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GENOTYPE_MODEL_VERSION "bb-research-v1"
/* Matches the bounded engine's maximum independent read population. */
#define GENOTYPE_MAX_DEPTH UINT64_C(1000000)

enum genotype_status {
    GENOTYPE_OK = 0,
    GENOTYPE_INVALID_CONFIG = 1,
    GENOTYPE_INVALID_COUNTS = 2,
    GENOTYPE_NUMERIC_ERROR = 3
};

extern const char GENOTYPE_ZERO_DEPTH[];
extern const char GENOTYPE_LOW_DEPTH[];
extern const char GENOTYPE_LOW_POSTERIOR[];
extern const char GENOTYPE_TIED[];

typedef struct genotype_config {
    double epsilon;
    double rho;
    double priors[3];
    uint64_t min_depth;
    double min_posterior;
} genotype_config;

typedef struct genotype_result {
    double posterior[3]; /* Ordered 0/0, 0/1, 1/1. */
    uint64_t effective_depth;
    int genotype; /* -1: no-call; 0, 1, 2: allele dosage. */
    const char *no_call_reason; /* NULL when called. Static storage; do not free. */
    const char *model_version;
    bool calibrated;
} genotype_result;

genotype_config genotype_default_config(void);
/* Nonzero status means no result is valid, never a default-model fallback.
 * Numeric operating domain: epsilon [1e-6, 0.5), rho [1e-6, 1-1e-6],
 * positive finite priors summing to one (absolute tolerance 1e-9).
 * The output is cleared to an invalid/no-call state before validation.
 */
int genotype_call(uint64_t ref, uint64_t alt,
                  const genotype_config *config, genotype_result *result);

#ifdef __cplusplus
}
#endif
#endif
