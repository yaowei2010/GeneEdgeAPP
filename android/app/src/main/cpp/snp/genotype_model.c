#include "genotype_model.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

const char GENOTYPE_ZERO_DEPTH[] = "ZERO_DEPTH";
const char GENOTYPE_LOW_DEPTH[] = "INSUFFICIENT_DEPTH";
const char GENOTYPE_LOW_POSTERIOR[] = "LOW_POSTERIOR";
const char GENOTYPE_TIED[] = "TIED_POSTERIOR";

genotype_config genotype_default_config(void) {
    const genotype_config c = {0.01, 0.02, {1.0/3.0,1.0/3.0,1.0/3.0}, 10, 0.99};
    return c;
}

static int valid_config(const genotype_config *c) {
    if (!c || !isfinite(c->epsilon) || c->epsilon < 1e-6 || c->epsilon >= 0.5 ||
        !isfinite(c->rho) || c->rho < 1e-6 || c->rho > 1.0-1e-6 ||
        !isfinite(c->min_posterior) || c->min_posterior < 0 || c->min_posterior > 1 ||
        c->min_depth > GENOTYPE_MAX_DEPTH) return 0;
    double sum = 0;
    for (int g=0;g<3;g++) {
        if (!isfinite(c->priors[g]) || c->priors[g] <= 0 || c->priors[g] > 1) return 0;
        sum += c->priors[g];
    }
    return fabs(sum-1) <= 1e-9;
}

int genotype_call(uint64_t ref, uint64_t alt,
                  const genotype_config *c, genotype_result *r) {
    if (!r) return GENOTYPE_INVALID_CONFIG;
    memset(r,0,sizeof(*r));
    r->genotype=-1;
    r->model_version=GENOTYPE_MODEL_VERSION;
    r->calibrated=false;
    if (!valid_config(c)) return GENOTYPE_INVALID_CONFIG;
    if (ref > GENOTYPE_MAX_DEPTH || alt > GENOTYPE_MAX_DEPTH-ref)
        return GENOTYPE_INVALID_COUNTS;
    const uint64_t depth=ref+alt;
    const double mu[3]={c->epsilon,0.5,1-c->epsilon};
    const double concentration=1/c->rho-1;
    double logs[3];
    for (int g=0;g<3;g++) {
        const double alpha=mu[g]*concentration;
        const double beta=(1-mu[g])*concentration;
        /* log C(n,a) and -log Gamma(n+alpha+beta) are common to all
         * genotypes. Cancel them before normalization to avoid needless
         * large-number subtraction; this yields identical posteriors. */
        logs[g]=lgamma((double)alt+alpha)-lgamma(alpha)
               +lgamma((double)ref+beta)-lgamma(beta)+log(c->priors[g]);
        if (!isfinite(logs[g])) return GENOTYPE_NUMERIC_ERROR;
    }
    int best=0;
    for (int g=1;g<3;g++) if (logs[g]>logs[best]) best=g;
    double sum=0;
    for (int g=0;g<3;g++) {r->posterior[g]=exp(logs[g]-logs[best]);sum+=r->posterior[g];}
    if (!isfinite(sum) || sum<=0) return GENOTYPE_NUMERIC_ERROR;
    for (int g=0;g<3;g++) r->posterior[g]/=sum;
    r->effective_depth=depth;
    if (!depth) r->no_call_reason=GENOTYPE_ZERO_DEPTH;
    else if (depth<c->min_depth) r->no_call_reason=GENOTYPE_LOW_DEPTH;
    else {
        int tied=0;
        for (int g=0;g<3;g++) if (g!=best && fabs(r->posterior[g]-r->posterior[best])<=1e-12) tied=1;
        if (tied) r->no_call_reason=GENOTYPE_TIED;
        else if (r->posterior[best]<c->min_posterior) r->no_call_reason=GENOTYPE_LOW_POSTERIOR;
        else r->genotype=best;
    }
    return GENOTYPE_OK;
}
