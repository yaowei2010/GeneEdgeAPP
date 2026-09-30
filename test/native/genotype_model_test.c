#include "genotype_model.h"
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

/* Independent small-depth reference: rising products, not log-gamma. */
static void reference(uint64_t r, uint64_t a, const genotype_config *c, double out[3]) {
    const long double mu[3] = {c->epsilon, 0.5L, 1.0L-c->epsilon};
    const long double concentration = 1.0L/c->rho-1.0L;
    long double weights[3], sum=0;
    for (int g=0;g<3;g++) {
        long double w=c->priors[g];
        for (uint64_t i=0;i<a;i++) w *= mu[g]*concentration+i;
        for (uint64_t i=0;i<r;i++) w *= (1.0L-mu[g])*concentration+i;
        for (uint64_t i=0;i<r+a;i++) w /= concentration+i;
        weights[g]=w; sum+=w;
    }
    for(int g=0;g<3;g++) out[g]=(double)(weights[g]/sum);
}
static void check_sum(const genotype_result *r) {
    double sum=0;
    for(int i=0;i<3;i++) {assert(isfinite(r->posterior[i]));assert(r->posterior[i]>=0);assert(r->posterior[i]<=1);sum+=r->posterior[i];}
    assert(fabs(sum-1)<1e-12);
}
int main(void) {
    genotype_config c=genotype_default_config();
    genotype_result x,y;
    assert(c.epsilon==0.01 && c.rho==0.02 && c.min_depth==10 && c.min_posterior==0.99);
    assert(genotype_call(4,4,&c,&x)==GENOTYPE_OK);
    assert(x.effective_depth==8 && x.genotype==-1 && x.no_call_reason==GENOTYPE_LOW_DEPTH);
    check_sum(&x);
    assert(genotype_call(0,0,&c,&x)==GENOTYPE_OK);
    assert(x.genotype==-1 && x.no_call_reason==GENOTYPE_ZERO_DEPTH);
    for(int i=0;i<3;i++) assert(fabs(x.posterior[i]-1.0/3)<1e-12);
    for(uint64_t r=0;r<=20;r++) for(uint64_t a=0;a<=20;a++) {
        double expected[3]; reference(r,a,&c,expected);
        assert(genotype_call(r,a,&c,&x)==GENOTYPE_OK);
        check_sum(&x);
        for(int i=0;i<3;i++) assert(fabs(x.posterior[i]-expected[i])<1e-11);
        assert(genotype_call(a,r,&c,&y)==GENOTYPE_OK);
        assert(fabs(x.posterior[0]-y.posterior[2])<1e-11);
        assert(fabs(x.posterior[1]-y.posterior[1])<1e-11);
    }
    assert(genotype_call(1000000,0,&c,&x)==GENOTYPE_OK);check_sum(&x);assert(x.genotype==0);
    assert(genotype_call(0,1000000,&c,&x)==GENOTYPE_OK);check_sum(&x);assert(x.genotype==2);
    assert(genotype_call(500000,500000,&c,&x)==GENOTYPE_OK);check_sum(&x);assert(x.genotype==1);
    const double valid_eps[]={1e-6,0.01,0.499999};
    const double valid_rho[]={1e-6,0.02,1-1e-6};
    for(unsigned e=0;e<3;e++) for(unsigned p=0;p<3;p++) {
        c=genotype_default_config();c.epsilon=valid_eps[e];c.rho=valid_rho[p];
        assert(genotype_call(12,8,&c,&x)==GENOTYPE_OK);check_sum(&x);
        double expected[3];reference(12,8,&c,expected);
        /* At high concentration, lgamma cancellation has ~1e-8 error. */
        for(int i=0;i<3;i++)assert(fabs(x.posterior[i]-expected[i])<1e-7);
        assert(genotype_call(1000000,0,&c,&x)==GENOTYPE_OK);check_sum(&x);
        assert(genotype_call(0,1000000,&c,&y)==GENOTYPE_OK);check_sum(&y);
        for(int i=0;i<3;i++)assert(fabs(x.posterior[i]-y.posterior[2-i])<1e-7);
    }
    c=genotype_default_config();
    assert(genotype_call(10,1,&c,&x)==GENOTYPE_OK);assert(x.genotype==-1 && x.no_call_reason==GENOTYPE_LOW_POSTERIOR);
    c.min_depth=0;c.min_posterior=0;
    double prior_sum=0;
    const double mu[3]={c.epsilon,0.5,1-c.epsilon};
    for(int i=0;i<3;i++){c.priors[i]=1/mu[i];prior_sum+=c.priors[i];}
    for(int i=0;i<3;i++)c.priors[i]/=prior_sum;
    assert(genotype_call(0,1,&c,&x)==GENOTYPE_OK);assert(x.genotype==-1 && x.no_call_reason==GENOTYPE_TIED);
    c=genotype_default_config();c.priors[0]=0.1;c.priors[1]=0.2;c.priors[2]=0.7;
    assert(genotype_call(0,0,&c,&x)==GENOTYPE_OK);for(int i=0;i<3;i++)assert(fabs(x.posterior[i]-c.priors[i])<1e-12);
    assert(genotype_call(UINT64_MAX,1,&c,&x)==GENOTYPE_INVALID_COUNTS);
    assert(genotype_call(GENOTYPE_MAX_DEPTH+1,0,&c,&x)==GENOTYPE_INVALID_COUNTS);
    const double bad_eps[]={0,-1,0.5,1,NAN,INFINITY,1e-300};
    for(unsigned i=0;i<sizeof(bad_eps)/sizeof(*bad_eps);i++){c=genotype_default_config();c.epsilon=bad_eps[i];assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);}
    const double bad_rho[]={0,-1,1,2,NAN,INFINITY,1e-300};
    for(unsigned i=0;i<sizeof(bad_rho)/sizeof(*bad_rho);i++){c=genotype_default_config();c.rho=bad_rho[i];assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);}
    c=genotype_default_config();c.priors[0]=0;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.priors[0]=NAN;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.priors[0]=0.5;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.min_posterior=1.1;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.min_posterior=-0.1;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.min_posterior=NAN;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();c.min_depth=GENOTYPE_MAX_DEPTH+1;assert(genotype_call(20,0,&c,&x)==GENOTYPE_INVALID_CONFIG);
    c=genotype_default_config();assert(genotype_call(20,0,NULL,&x)==GENOTYPE_INVALID_CONFIG);assert(genotype_call(20,0,&c,NULL)==GENOTYPE_INVALID_CONFIG);
    puts("genotype model tests passed");
    return 0;
}
