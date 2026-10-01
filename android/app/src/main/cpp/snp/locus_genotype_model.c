#include "locus_genotype_model.h"
#include <math.h>
#include <string.h>

locus_genotype_config locus_genotype_default_config(void) {
    locus_genotype_config c={.01,.02,{0},10,.99};
    for(int g=0;g<10;g++)c.priors[g]=.1;
    return c;
}
int locus_genotype_call(const uint64_t counts[4],const locus_genotype_config *c,
                         locus_genotype_result *r) {
    if(!r)return LOCUS_GENOTYPE_INVALID_COUNTS;
    memset(r,0,sizeof *r);r->best_i=r->best_j=-1;
    if(!counts)return LOCUS_GENOTYPE_INVALID_COUNTS;
    if(!c||!isfinite(c->epsilon)||c->epsilon<1e-6||c->epsilon>=.5||
       !isfinite(c->rho)||c->rho<1e-6||c->rho>1-1e-6||
       !isfinite(c->min_posterior)||c->min_posterior<0||c->min_posterior>1||c->min_depth>1000000)
        return LOCUS_GENOTYPE_INVALID_CONFIG;
    double prior_sum=0;
    for(int g=0;g<10;g++){
        if(!isfinite(c->priors[g])||c->priors[g]<=0)return LOCUS_GENOTYPE_INVALID_CONFIG;
        prior_sum+=c->priors[g];
    }
    if(!isfinite(prior_sum)||fabs(prior_sum-1)>1e-9)return LOCUS_GENOTYPE_INVALID_CONFIG;
    uint64_t n=0;
    for(int b=0;b<4;b++){
        if(counts[b]>1000000-n)return LOCUS_GENOTYPE_INVALID_COUNTS;
        n+=counts[b];
    }
    double scores[10],concentration=1/c->rho-1;int g=0,best=0;
    /* Omit common gamma(concentration)/gamma(n+concentration) and
     * multinomial coefficient; they cancel across genotypes. */
    for(int i=0;i<4;i++)for(int j=i;j<4;j++,g++){
        double score=log(c->priors[g]);
        for(int b=0;b<4;b++){
            double dosage=((b==i)+(b==j))/2.0;
            double mu=dosage*(1-c->epsilon)+(1-dosage)*c->epsilon/3;
            double alpha=mu*concentration;
            score+=lgamma((double)counts[b]+alpha)-lgamma(alpha);
        }
        if(!isfinite(score))return LOCUS_GENOTYPE_NUMERIC_ERROR;
        scores[g]=score;if(score>scores[best])best=g;
    }
    double sum=0;
    for(g=0;g<10;g++){r->posterior[g]=exp(scores[g]-scores[best]);sum+=r->posterior[g];}
    if(!isfinite(sum)||sum<=0){memset(r,0,sizeof *r);return LOCUS_GENOTYPE_NUMERIC_ERROR;}
    double second=-INFINITY;
    for(g=0;g<10;g++){r->posterior[g]/=sum;if(g!=best&&scores[g]>second)second=scores[g];}
    g=0;for(int i=0;i<4;i++)for(int j=i;j<4;j++,g++)if(g==best){r->best_i=i;r->best_j=j;}
    r->effective_depth=n;r->best_posterior=r->posterior[best];r->log_score_gap=scores[best]-second;
    r->model_version="dm-locus-research-v1";r->calibrated=false;
    if(!n)r->no_call_reason="ZERO_DEPTH";
    else if(n<c->min_depth)r->no_call_reason="LOW_DEPTH";
    else if(r->log_score_gap<=1e-12)r->no_call_reason="TIED";
    else if(r->best_posterior<c->min_posterior)r->no_call_reason="LOW_POSTERIOR";
    else r->called=true;
    return LOCUS_GENOTYPE_OK;
}
