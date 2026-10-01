#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
/* Reuse the existing deterministic sparse-fixture helpers, not patient data. */
#define main legacy_test_main
#include "snp_engine_test.c"
#undef main

int main(void) {
    int idx=tempfile(),ids=tempfile();clear_fixture(idx,ids);
    char seq[302],alleles[4][302];sequence(seq);
    for(int a=0;a<4;a++){memcpy(alleles[a],seq,302);alleles[a][150]="ACGT"[a];}
    const char *queries[]={alleles[0],alleles[1],alleles[2]};
    assert(snp_locus_validate(queries,"AAA",3)==SNP_OK);
    assert(snp_locus_validate(queries,"ACA",3)==SNP_INVALID_QUERY);
    alleles[1][0]=complement(alleles[1][0]);
    assert(snp_locus_validate(queries,"AAA",3)==SNP_INVALID_QUERY);
    alleles[1][0]=seq[0];
    assert(snp_locus_validate(NULL,NULL,0)==SNP_INVALID_QUERY);
    uint32_t all[]={0,1,2,3,4,5,UINT32_MAX,0};
    uint32_t support[4][3]={{0,4,0},{1,4,1},{2,UINT32_MAX,2},{3,UINT32_MAX,3}};
    uint64_t off=(UINT64_C(1)<<32)+1;
    for(int o=0;o<2;o++){
        char oriented[4][302];
        for(int a=0;a<4;a++){
            for(int i=0;i<301;i++)oriented[a][i]=o?complement(alleles[a][300-i]):alleles[a][i];
            oriented[a][301]=0;
        }
        for(int p=0;p<=288;p+=2){
            if(p>=138&&p<=150){
                for(int a=0;a<4;a++){bucket(idx,ids,hash(oriented[a]+p),off,support[a],3);off+=3;}
            }else{bucket(idx,ids,hash(oriented[0]+p),off,all,8);off+=8;}
        }
    }
    snp_locus_counts c,measured;snp_timing timing;
    assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_OK);
    assert(c.total==7&&c.ambiguous==2&&c.coverage_only==1);
    for(int a=0;a<4;a++)assert(c.bases[a]==1);
    assert(snp_locus_query(idx,ids,seq,&measured,NULL,NULL,&timing)==SNP_OK);
    assert(memcmp(&c,&measured,sizeof c)==0&&timing.io_ns>0&&timing.query_ns>=timing.io_ns);
    assert(snp_locus_query(idx,ids,seq,&c,cancel,NULL,NULL)==SNP_CANCELLED&&c.total==0);
    assert(snp_locus_query(idx,ids,"A",&c,NULL,NULL,NULL)==SNP_INVALID_QUERY);
    seq[0]='N';assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_INVALID_QUERY);sequence(seq);
    clear_fixture(idx,ids);off=0;
    uint32_t repeated[]={42,42};
    for(int p=0;p<116;p+=2){bucket(idx,ids,hash(seq+p),off,repeated,2);off+=2;}
    assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_OK&&c.total==0);
    bucket(idx,ids,hash(seq+116),off,repeated,2);off+=2;
    assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_OK&&c.coverage_only==1);
    unsigned char data[8];le(data,0xffffffffu);le(data+4,0xffffffffu);
    assert(pwrite(idx,data,8,(off_t)hash(seq)*8)==8);
    assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_INVALID_FORMAT&&c.total==0);
    clear_fixture(idx,ids);assert(ftruncate(ids,65537*4)==0);
    le(data,0);le(data+4,65537);assert(pwrite(idx,data,8,(off_t)hash(seq)*8)==8);
    assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_OK&&c.skipped_buckets==1);
    truncate_context tc={idx,0};
    assert(snp_locus_query(idx,ids,seq,&c,truncate_during_query,&tc,NULL)==SNP_IO_ERROR);
    clear_fixture(idx,ids);uint32_t *many=malloc(65536*sizeof *many);assert(many);
    for(int k=0;k<16;k++){
        for(uint32_t j=0;j<65536;j++)many[j]=(uint32_t)k*65536+j;
        bucket(idx,ids,hash(seq+k*2),(uint64_t)k*65536,many,65536);
    }
    free(many);assert(snp_locus_query(idx,ids,seq,&c,NULL,NULL,NULL)==SNP_RESOURCE_LIMIT&&c.total==0);
    int pipes[2];assert(pipe(pipes)==0);
    assert(snp_locus_query(pipes[0],ids,seq,&c,NULL,NULL,NULL)==SNP_NOT_SEEKABLE);
    close(pipes[0]);close(pipes[1]);close(idx);close(ids);
    puts("Joint locus C evidence tests passed");return 0;
}
