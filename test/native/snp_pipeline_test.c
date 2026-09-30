#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include "../../android/app/src/main/cpp/snp/snp_engine.h"
#include "../../android/app/src/main/cpp/snp/genotype_model.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int temporary(void) {
    char name[]="/tmp/gene-pipeline-XXXXXX";
    int fd=mkstemp(name);assert(fd>=0);assert(unlink(name)==0);return fd;
}
static void le(unsigned char *p,uint32_t x) { for(int i=0;i<4;i++)p[i]=(unsigned char)(x>>(8*i)); }
static void posting(int idx,int ids,const char *seq,uint64_t *offset,const uint32_t *reads,uint32_t count) {
    uint32_t hash=0;for(int i=0;i<13;i++)hash=(hash<<2)|(((unsigned char)seq[i]>>1)&3u);
    unsigned char data[8];le(data,(uint32_t)*offset);le(data+4,count|((uint32_t)(*offset>>32)<<24));
    assert(pwrite(idx,data,8,(off_t)hash*8)==8);
    for(uint32_t i=0;i<count;i++){le(data,reads[i]);assert(pwrite(ids,data,4,(off_t)(*offset+i)*4)==4);}
    *offset+=count;
}
int main(void) {
    int idx=temporary(),ids=temporary();assert(ftruncate(idx,536870912)==0);
    /* Sparse fixture starts above 4 GiB. No patient data or large disk allocation. */
    uint64_t offset=(UINT64_C(1)<<30)+1;
    char ref[302],alt[302];uint32_t seed=123456789;
    for(int i=0;i<301;i++){seed^=seed<<13;seed^=seed>>17;seed^=seed<<5;ref[i]="ACTG"[seed&3];}
    ref[150]='A';ref[301]=0;memcpy(alt,ref,sizeof alt);alt[150]='C';
    uint32_t all[42],r[21],a[21];
    for(uint32_t i=0;i<42;i++)all[i]=i;
    for(uint32_t i=0;i<20;i++){r[i]=i;a[i]=i+20;}r[20]=a[20]=40;
    for(int i=0;i<=288;i+=2){
        if(i>=138&&i<=150){posting(idx,ids,ref+i,&offset,r,21);posting(idx,ids,alt+i,&offset,a,21);}
        else posting(idx,ids,ref+i,&offset,all,42);
    }
    snp_counts counts;assert(snp_query(idx,ids,ref,'A','C',&counts,NULL,NULL)==SNP_OK);
    assert(counts.total==42&&counts.ref==20&&counts.alt==20&&counts.ambiguous==1&&counts.coverage_only==1);
    genotype_config config=genotype_default_config();genotype_result result;
    assert(genotype_call(counts.ref,counts.alt,&config,&result)==GENOTYPE_OK);
    assert(result.effective_depth==40&&result.genotype==1&&result.posterior[1]>=0.99);
    assert(!result.calibrated&&strcmp(result.model_version,"bb-research-v1")==0);
    /* Ambiguous and coverage-only evidence must never inflate model depth. */
    assert(genotype_call(4,4,&config,&result)==GENOTYPE_OK);
    assert(result.effective_depth==8&&result.genotype==-1);
    close(idx);close(ids);puts("C SNP-to-genotype pipeline tests passed");return 0;
}
