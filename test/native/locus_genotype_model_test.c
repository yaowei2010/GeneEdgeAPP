#include "../../android/app/src/main/cpp/snp/locus_genotype_model.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

/* Independent long-double reference evaluates gamma ratios as a rising
 * factorial, not the production lgamma expression. */
static void reference(const uint64_t counts[4],const locus_genotype_config *c,long double out[10]) {
    long double sum=0;int g=0;
    for(int i=0;i<4;i++)for(int j=i;j<4;j++,g++){
        long double score=logl(c->priors[g]);
        for(int b=0;b<4;b++){
            long double d=((b==i)+(b==j))/2.0L;
            long double mu=d*(1-c->epsilon)+(1-d)*c->epsilon/3;
            long double alpha=mu*(1/c->rho-1);
            for(uint64_t k=0;k<counts[b];k++)score+=logl(alpha+k);
        }
        out[g]=score;
    }
    long double max=out[0];for(int k=1;k<10;k++)if(out[k]>max)max=out[k];
    for(int k=0;k<10;k++){out[k]=expl(out[k]-max);sum+=out[k];}
    for(int k=0;k<10;k++)out[k]/=sum;
}
int main(void) {
    locus_genotype_config c=locus_genotype_default_config();locus_genotype_result r;
    uint64_t counts[4]={0,100,100,0};
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK);
    assert(r.best_i==1&&r.best_j==2&&r.called&&r.best_posterior>=.99);
    assert(r.effective_depth==200&&r.log_score_gap>0);
    assert(!r.calibrated&&strcmp(r.model_version,"dm-locus-research-v1")==0);
    long double expected[10];reference(counts,&c,expected);double sum=0;
    for(int g=0;g<10;g++){assert(fabs(r.posterior[g]-(double)expected[g])<1e-10);sum+=r.posterior[g];}
    assert(fabs(sum-1)<1e-12);
    for(int i=0;i<4;i++)for(int j=i;j<4;j++){
        memset(counts,0,sizeof counts);counts[i]+=100;counts[j]+=100;
        assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK&&r.best_i==i&&r.best_j==j&&r.called);
    }
    memset(counts,0,sizeof counts);
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK&&!r.called&&strcmp(r.no_call_reason,"ZERO_DEPTH")==0);
    counts[0]=4;counts[1]=4;
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK&&!r.called&&strcmp(r.no_call_reason,"LOW_DEPTH")==0);
    for(int b=0;b<4;b++)counts[b]=100;
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK&&!r.called&&strcmp(r.no_call_reason,"TIED")==0);
    counts[0]=1000000;counts[1]=counts[2]=counts[3]=0;
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK);
    counts[1]=1;assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_INVALID_COUNTS);
    counts[0]=UINT64_MAX;assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_INVALID_COUNTS);
    counts[0]=0;counts[1]=20;c.min_posterior=1;
    assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_OK&&!r.called&&strcmp(r.no_call_reason,"LOW_POSTERIOR")==0);
    c.epsilon=NAN;assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_INVALID_CONFIG);
    c=locus_genotype_default_config();c.rho=0;assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_INVALID_CONFIG);
    c=locus_genotype_default_config();c.priors[0]=0;assert(locus_genotype_call(counts,&c,&r)==LOCUS_GENOTYPE_INVALID_CONFIG);
    assert(locus_genotype_call(NULL,&c,&r)==LOCUS_GENOTYPE_INVALID_COUNTS);
    puts("Joint locus statistical model tests passed");return 0;
}
