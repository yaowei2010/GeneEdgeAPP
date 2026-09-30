#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include "snp_engine.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define IDX_BYTES UINT64_C(536870912)
#define SNP_CANDIDATE_LIMIT 1000000u
#define BATCH 4096u
typedef char require_64_bit_offsets[(sizeof(off_t)>=8)?1:-1];
typedef struct {
    uint32_t id;
    uint16_t coverage[2], refs[2], alts[2];
    uint16_t last_coverage, last_ref, last_alt;
} candidate;
/* Position tokens advance monotonically. Tracking the last token per category
 * deduplicates a posting without allocating a bitmap per read. Each table has
 * at most 2^21 slots (48 MiB), with at most 72 MiB transient during rehash. */
typedef struct { candidate *slots; size_t capacity, used; } table;

static uint32_t decode(const unsigned char *b) {
    return (uint32_t)b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);
}
static uint32_t hash(const char *s) {
    uint32_t h=0;
    for(int i=0;i<13;i++)h=(h<<2)|(((unsigned char)s[i]>>1)&3u);
    return h;
}
static size_t mix(uint32_t x) {
    x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;x^=x>>16;return x;
}
static candidate *locate(table *t,uint32_t id) {
    size_t i=mix(id)&(t->capacity-1);
    while(t->slots[i].last_coverage && t->slots[i].id!=id)i=(i+1)&(t->capacity-1);
    return &t->slots[i];
}
static int grow(table *t) {
    size_t capacity=t->capacity?t->capacity*2:1024;
    candidate *slots=calloc(capacity,sizeof *slots);
    if(!slots)return SNP_RESOURCE_LIMIT;
    table next={slots,capacity,t->used};
    for(size_t i=0;i<t->capacity;i++)if(t->slots[i].last_coverage)*locate(&next,t->slots[i].id)=t->slots[i];
    free(t->slots);*t=next;return SNP_OK;
}
static int read_at(int fd,unsigned char *buffer,size_t bytes,uint64_t offset) {
    while(bytes){
        ssize_t n=pread(fd,buffer,bytes,(off_t)offset);
        if(n<0){if(errno==EINTR)continue;return errno==ESPIPE?SNP_NOT_SEEKABLE:SNP_IO_ERROR;}
        if(n==0)return SNP_IO_ERROR;
        buffer+=n;bytes-=(size_t)n;offset+=(uint64_t)n;
    }
    return SNP_OK;
}
static int base(char c){return c=='A'||c=='C'||c=='G'||c=='T';}
static char complement(char c){return c=='A'?'T':c=='T'?'A':c=='C'?'G':'C';}
const char *snp_error_code(int e) {
    switch(e){case SNP_OK:return "OK";case SNP_INVALID_QUERY:return "INVALID_QUERY";
    case SNP_INVALID_FORMAT:return "INVALID_FORMAT";case SNP_NOT_SEEKABLE:return "NOT_SEEKABLE";
    case SNP_IO_ERROR:return "IO_ERROR";case SNP_RESOURCE_LIMIT:return "RESOURCE_LIMIT";
    case SNP_CANCELLED:return "CANCELLED";default:return "IO_ERROR";}
}
int snp_query(int idxfd,int idsfd,const char *sequence,char ref,char alt,
              snp_counts *out,snp_cancel_fn cancelled,void *context) {
    if(!out)return SNP_INVALID_QUERY;
    memset(out,0,sizeof *out);
    if(!sequence||!base(ref)||!base(alt)||ref==alt)return SNP_INVALID_QUERY;
    for(int i=0;i<301;i++)if(!base(sequence[i]))return SNP_INVALID_QUERY;
    if(sequence[301] || (sequence[150]!=ref && sequence[150]!=alt))return SNP_INVALID_QUERY;
    if(cancelled && cancelled(context))return SNP_CANCELLED;
    if(lseek(idxfd,0,SEEK_CUR)<0 || lseek(idsfd,0,SEEK_CUR)<0)
        return errno==ESPIPE?SNP_NOT_SEEKABLE:SNP_IO_ERROR;
    struct stat is,ds;
    if(fstat(idxfd,&is)||fstat(idsfd,&ds))return SNP_IO_ERROR;
    if(is.st_size!=(off_t)IDX_BYTES||ds.st_size<=0||ds.st_size%4)return SNP_INVALID_FORMAT;
    const uint64_t postings=(uint64_t)ds.st_size/4;
    char sequences[2][2][302];
    for(int a=0;a<2;a++){
        memcpy(sequences[0][a],sequence,302);sequences[0][a][150]=a?alt:ref;
        for(int i=0;i<301;i++)sequences[1][a][i]=complement(sequences[0][a][300-i]);
        sequences[1][a][301]=0;
    }
    table t={NULL,0,0};int error=grow(&t);snp_counts result={0};
    unsigned char bucket[8],batch[BATCH*4];
    if(error)goto done;
    for(int orientation=0;orientation<2;orientation++)for(int position=0;position<=288;position+=2){
        const uint16_t token=(uint16_t)(orientation*145+position/2+1);
        const int overlap=position<=150 && position+12>=150;
        for(int allele=0;allele<(overlap?2:1);allele++){
            if(cancelled && cancelled(context)){error=SNP_CANCELLED;goto done;}
            error=read_at(idxfd,bucket,8,(uint64_t)hash(sequences[orientation][allele]+position)*8);
            if(error)goto done;
            uint32_t packed=decode(bucket+4),count=packed&0xffffffu;
            uint64_t offset=decode(bucket)|((uint64_t)(packed>>24)<<32);
            if(offset>postings || count>postings-offset){error=SNP_INVALID_FORMAT;goto done;}
            if(count>65536){result.skipped_buckets++;continue;}
            for(uint32_t start=0;start<count;){
                if(cancelled && cancelled(context)){error=SNP_CANCELLED;goto done;}
                uint32_t take=count-start;if(take>BATCH)take=BATCH;
                error=read_at(idsfd,batch,(size_t)take*4,(offset+start)*4);if(error)goto done;
                for(uint32_t j=0;j<take;j++){
                    uint32_t id=decode(batch+j*4);candidate *c=locate(&t,id);
                    if(!c->last_coverage){
                        if(t.used>=SNP_CANDIDATE_LIMIT){error=SNP_RESOURCE_LIMIT;goto done;}
                        if((t.used+1)*10>t.capacity*7){error=grow(&t);if(error)goto done;c=locate(&t,id);}
                        c->id=id;t.used++;
                    }
                    if(c->last_coverage!=token){c->coverage[orientation]++;c->last_coverage=token;}
                    if(overlap){
                        uint16_t *last=allele?&c->last_alt:&c->last_ref;
                        if(*last!=token){(allele?c->alts:c->refs)[orientation]++;*last=token;}
                    }
                }
                start+=take;
            }
        }
    }
    for(size_t i=0;i<t.capacity;i++){
        if((i&4095u)==0 && cancelled && cancelled(context)){error=SNP_CANCELLED;goto done;}
        candidate *c=&t.slots[i];if(!c->last_coverage)continue;
        unsigned r=0,a=0;int qualified=0;
        /* Do not promote weak evidence from a nonqualifying orientation. */
        for(int o=0;o<2;o++)if(c->coverage[o]>58){qualified=1;r+=c->refs[o];a+=c->alts[o];}
        if(!qualified)continue;
        result.total++;
        if(!r&&!a)result.coverage_only++;
        else if(r==a)result.ambiguous++;
        else if(r>a)result.ref++;
        else result.alt++;
    }
done:
    free(t.slots);if(error==SNP_OK)*out=result;return error;
}
