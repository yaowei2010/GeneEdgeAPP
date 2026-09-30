#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include "../../android/app/src/main/cpp/snp/snp_engine.h"
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint32_t hash(const char *s) {
    uint32_t h = 0;
    for (int j = 0; j < 13; j++) h = (h << 2) | (((unsigned char)s[j] >> 1) & 3u);
    return h;
}
static void le(unsigned char *p, uint32_t x) {
    for (int i=0;i<4;i++) p[i]=(unsigned char)(x>>(8*i));
}
static int tempfile(void) {
    char p[]="/tmp/gene-snp-XXXXXX";
    int fd=mkstemp(p); assert(fd>=0); assert(unlink(p)==0); return fd;
}
static void bucket(int idx,int ids,uint32_t h,uint64_t posting,const uint32_t *reads,uint32_t n) {
    unsigned char b[8]; le(b,(uint32_t)posting); le(b+4,n|((uint32_t)(posting>>32)<<24));
    assert(pwrite(idx,b,8,(off_t)h*8)==8);
    unsigned char *payload=malloc((size_t)n*4);assert(payload);
    for(uint32_t i=0;i<n;i++)le(payload+i*4,reads[i]);
    assert(pwrite(ids,payload,(size_t)n*4,(off_t)posting*4)==(ssize_t)n*4);free(payload);
}
static void sequence(char s[302]) {
    uint32_t x=123456789;
    for(int i=0;i<301;i++){x^=x<<13;x^=x>>17;x^=x<<5;s[i]="ACTG"[x&3];}
    s[150]='A'; s[301]=0;
}
static int cancel(void *p){ (void)p;return 1; }
static char complement(char c){return c=='A'?'T':c=='T'?'A':c=='C'?'G':'C';}
static void clear_fixture(int idx,int ids){assert(ftruncate(idx,0)==0);assert(ftruncate(idx,536870912)==0);assert(ftruncate(ids,4)==0);}
typedef struct {int fd,calls;} truncate_context;
static int truncate_during_query(void *p){truncate_context *c=p;if(++c->calls==2)assert(ftruncate(c->fd,0)==0);return 0;}
int main(void) {
    int idx=tempfile(),ids=tempfile();
    assert(ftruncate(idx,536870912)==0); assert(ftruncate(ids,4)==0);
    char seq[302];sequence(seq);snp_counts c;
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==0);
    assert(snp_query(idx,ids,seq,'A','A',&c,NULL,NULL)==SNP_INVALID_QUERY);
    assert(snp_query(idx,ids,"A",'A','C',&c,NULL,NULL)==SNP_INVALID_QUERY);
    seq[0]='N';assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_INVALID_QUERY);sequence(seq);
    assert(snp_query(idx,ids,seq,'A','C',&c,cancel,NULL)==SNP_CANCELLED);

    /* One read repeated twice in every background bucket: independent depth is one. */
    uint32_t reads[]={42,42};uint64_t off=0;
    for(int i=0;i<=288;i+=2){bucket(idx,ids,hash(seq+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==1 && c.ref==1 && c.alt==0);
    /* Add equal ALT support at each center-overlapping position: ambiguous. */
    char alt[302];memcpy(alt,seq,sizeof alt);alt[150]='C';
    for(int i=138;i<=150;i+=2){bucket(idx,ids,hash(alt+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==1 && c.ambiguous==1 && c.ref==0 && c.alt==0);
    assert(c.total==c.ref+c.alt+c.ambiguous+c.coverage_only);
    unsigned char zero[8]={0};assert(pwrite(idx,zero,8,(off_t)hash(alt+138)*8)==8);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.ref==1 && c.ambiguous==0);
    bucket(idx,ids,hash(alt+138),off,reads,2);off+=2;
    /* Both orientations hit the same read, but total independent read count stays one. */
    char reverse[302],reverse_alt[302];
    for(int i=0;i<301;i++){reverse[i]=complement(seq[300-i]);reverse_alt[i]=complement(alt[300-i]);}
    reverse[301]=reverse_alt[301]=0;
    for(int i=0;i<=288;i+=2){bucket(idx,ids,hash(reverse+i),off,reads,2);off+=2;}
    for(int i=138;i<=150;i+=2){bucket(idx,ids,hash(reverse_alt+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==1 && c.ambiguous==1);

    /* Little-endian packed 40-bit posting index crosses the 4 GiB byte boundary. */
    uint64_t large=UINT64_C(1)<<32;bucket(idx,ids,hash(seq),large,reads,2);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==1);
    /* Range validation applies even to high-frequency buckets, not silent skipping. */
    unsigned char b[8];le(b,0xffffffffu);le(b+4,0xffffffffu);
    assert(pwrite(idx,b,8,(off_t)hash(seq)*8)==8);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_INVALID_FORMAT);
    assert(c.total==0);
    /* Shared background is counted once: exactly 58 positions never qualifies. */
    clear_fixture(idx,ids);off=0;
    for(int i=0;i<116;i+=2){bucket(idx,ids,hash(seq+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.total==0);
    bucket(idx,ids,hash(seq+116),off,reads,2);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.total==1 && c.coverage_only==1);
    off+=2;
    /* ALT support in an orientation with only seven positions cannot promote a call. */
    for(int i=138;i<=150;i+=2){bucket(idx,ids,hash(reverse_alt+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.total==1 && c.coverage_only==1);
    for(int i=138;i<=150;i+=2){bucket(idx,ids,hash(seq+i),off,reads,2);off+=2;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.total==1 && c.ref==1);
    /* uint32 keys include zero and the upper file-index bit without aliasing. */
    clear_fixture(idx,ids);off=0;uint32_t extremes[]={0,UINT32_MAX,42};
    for(int i=0;i<=288;i+=2){bucket(idx,ids,hash(alt+i),off,extremes,3);off+=3;}
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);assert(c.total==3 && c.alt==3);
    /* A high-frequency bucket reports a skip, without making any support. */
    clear_fixture(idx,ids);assert(ftruncate(ids,65537*4)==0);
    le(b,0);le(b+4,65537);assert(pwrite(idx,b,8,(off_t)hash(seq)*8)==8);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_OK);
    assert(c.total==0 && c.skipped_buckets==1);
    /* A disappeared/truncated source is IO_ERROR, never a successful empty result. */
    truncate_context tc={idx,0};
    assert(snp_query(idx,ids,seq,'A','C',&c,truncate_during_query,&tc)==SNP_IO_ERROR);
    /* More than one million unique candidates fails; no truncation succeeds. */
    clear_fixture(idx,ids);uint32_t *many=malloc(65536*sizeof *many);assert(many);
    for(int k=0;k<16;k++){
        for(uint32_t j=0;j<65536;j++)many[j]=(uint32_t)k*65536+j;
        bucket(idx,ids,hash(seq+k*2),(uint64_t)k*65536,many,65536);
    }
    free(many);assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_RESOURCE_LIMIT);
    assert(c.total==0);
    assert(ftruncate(idx,8)==0);
    assert(snp_query(idx,ids,seq,'A','C',&c,NULL,NULL)==SNP_INVALID_FORMAT);
    int pipes[2];assert(pipe(pipes)==0);
    assert(snp_query(pipes[0],ids,seq,'A','C',&c,NULL,NULL)==SNP_NOT_SEEKABLE);
    close(pipes[0]);close(pipes[1]);close(idx);close(ids);
    puts("snp_engine tests passed");return 0;
}
