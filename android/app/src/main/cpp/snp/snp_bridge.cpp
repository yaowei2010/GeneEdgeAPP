#include <jni.h>
#include <unistd.h>
#include <sstream>
#include <iomanip>
#include <locale>
#include <new>
#include <chrono>
#include <vector>
#include <algorithm>
#include "snp_engine.h"
#include "snp_timing.h"
#include "genotype_model.h"
#include "locus_genotype_model.h"

namespace {
struct Descriptor { int fd; ~Descriptor() { if(fd >= 0) close(fd); } };
struct Utf {
    JNIEnv* env; jstring value; const char* text;
    Utf(JNIEnv* e, jstring v):env(e),value(v),text(v ? e->GetStringUTFChars(v,nullptr) : nullptr) {}
    ~Utf() { if(text) env->ReleaseStringUTFChars(value,text); }
};
struct Cancellation { JNIEnv* env; jobject owner; jmethodID method; jlong token; };
int cancelled(void* value) {
    auto* c = static_cast<Cancellation*>(value);
    const jboolean result = c->env->CallBooleanMethod(c->owner,c->method,c->token);
    return c->env->ExceptionCheck() || result == JNI_TRUE;
}
jstring error(JNIEnv* env,const char* code) {
    std::string text = std::string("{\"errorCode\":\"") + code + "\"}";
    return env->NewStringUTF(text.c_str());
}
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_SnpComputePlugin_nativeCompute(JNIEnv* env,jobject owner,jint idx,jint ids,
    jstring sequence,jstring ref,jstring alt,jlong token,jboolean debug) try {
    using Clock=std::chrono::steady_clock;
    const auto began=debug?Clock::now():Clock::time_point{};
    Descriptor index{dup(idx)}, postings{dup(ids)};
    if(index.fd < 0 || postings.fd < 0) return error(env,"IO_ERROR");
    Utf query(env,sequence);
    if(env->ExceptionCheck()) return nullptr;
    Utf r(env,ref);
    if(env->ExceptionCheck()) return nullptr;
    Utf a(env,alt);
    if(env->ExceptionCheck()) return nullptr;
    if(!query.text || !r.text || !a.text || !r.text[0] || r.text[1] || !a.text[0] || a.text[1]) return error(env,"INVALID_QUERY");
    jclass cls = env->GetObjectClass(owner);
    if(!cls) return nullptr;
    jmethodID method = env->GetMethodID(cls,"isCancelled","(J)Z"); env->DeleteLocalRef(cls);
    if(!method) return nullptr;
    Cancellation cancel{env,owner,method,token}; snp_counts counts{};
    snp_timing timing{};
    int status = snp_query_timed(index.fd,postings.fd,query.text,r.text[0],a.text[0],&counts,cancelled,&cancel,debug?&timing:nullptr);
    if(env->ExceptionCheck()) return nullptr;
    if(status != SNP_OK) return error(env,snp_error_code(status));
    genotype_config config = genotype_default_config(); genotype_result result{};
    const auto model_start=debug?Clock::now():Clock::time_point{};
    if(genotype_call(counts.ref,counts.alt,&config,&result) != GENOTYPE_OK) return error(env,"INVALID_MODEL");
    const auto model_end=debug?Clock::now():Clock::time_point{};
    snp_stage_timing stages{};
    if(debug && snp_split_timing(timing.query_ns,timing.io_ns,
        static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(model_end-model_start).count()),
        static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(model_end-began).count()),&stages)!=SNP_OK)
        return error(env,"IO_ERROR");
    std::ostringstream out; out.imbue(std::locale::classic()); out << std::setprecision(17);
    const char* gt = result.genotype == 0 ? "0/0" : result.genotype == 1 ? "0/1" : result.genotype == 2 ? "1/1" : "./.";
    out << "{\"total\":" << counts.total << ",\"ref\":" << counts.ref << ",\"alt\":" << counts.alt
        << ",\"ambiguous\":" << counts.ambiguous << ",\"coverageOnly\":" << counts.coverage_only
        << ",\"skippedBuckets\":" << counts.skipped_buckets << ",\"effectiveDepth\":" << result.effective_depth
        << ",\"posterior\":[" << result.posterior[0] << ',' << result.posterior[1] << ',' << result.posterior[2]
        << "],\"gt\":\"" << gt << "\",\"noCallReason\":";
    if(result.no_call_reason) out << '"' << result.no_call_reason << '"'; else out << "null";
    out << ",\"modelVersion\":\"" << result.model_version << "\",\"calibrated\":false,\"parameters\":{\"epsilon\":"
        << config.epsilon << ",\"rho\":" << config.rho << ",\"priors\":[" << config.priors[0] << ',' << config.priors[1]
        << ',' << config.priors[2] << "],\"minDepth\":" << config.min_depth << ",\"minPosterior\":" << config.min_posterior << "}";
    if(debug) out << ",\"debugTiming\":{\"ioMs\":" << stages.io_ms << ",\"countMs\":" << stages.count_ms
        << ",\"genotypeMs\":" << stages.genotype_ms << ",\"nativeOverheadMs\":" << stages.overhead_ms
        << ",\"nativeTotalMs\":" << stages.total_ms << '}';
    out << '}';
    return env->NewStringUTF(out.str().c_str());
} catch(const std::bad_alloc&) {
    return env->ExceptionCheck() ? nullptr : env->NewStringUTF("{\"errorCode\":\"RESOURCE_LIMIT\"}");
} catch(...) {
    return env->ExceptionCheck() ? nullptr : env->NewStringUTF("{\"errorCode\":\"IO_ERROR\"}");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_SnpComputePlugin_nativeComputeLocus(JNIEnv* env,jobject owner,jint idx,jint ids,
    jobjectArray sequences,jstring ref,jlong token,jboolean debug) try {
    using Clock=std::chrono::steady_clock;
    const auto began=debug?Clock::now():Clock::time_point{};
    Descriptor index{dup(idx)},postings{dup(ids)};
    if(index.fd<0||postings.fd<0)return error(env,"IO_ERROR");
    Utf r(env,ref);if(env->ExceptionCheck())return nullptr;
    if(!r.text||!r.text[0]||r.text[1]||!sequences)return error(env,"INVALID_QUERY");
    const int count=env->GetArrayLength(sequences);
    if(count<1||count>4)return error(env,"INVALID_QUERY");
    std::vector<std::string> strings;
    for(int i=0;i<count;i++){
        jstring s=static_cast<jstring>(env->GetObjectArrayElement(sequences,i));
        if(env->ExceptionCheck())return nullptr;
        { Utf q(env,s);if(env->ExceptionCheck())return nullptr;
          if(!q.text){env->DeleteLocalRef(s);return error(env,"INVALID_QUERY");}
          strings.emplace_back(q.text); }
        env->DeleteLocalRef(s);
    }
    std::vector<const char*> queries;for(const auto& s:strings)queries.push_back(s.c_str());
    std::string refs(static_cast<size_t>(count),r.text[0]);
    if(snp_locus_validate(queries.data(),refs.c_str(),queries.size())!=SNP_OK)return error(env,"INVALID_QUERY");
    jclass cls=env->GetObjectClass(owner);if(!cls)return nullptr;
    jmethodID method=env->GetMethodID(cls,"isCancelled","(J)Z");env->DeleteLocalRef(cls);if(!method)return nullptr;
    Cancellation cancel{env,owner,method,token};snp_locus_counts counts{};snp_timing timing{};
    int status=snp_locus_query(index.fd,postings.fd,queries[0],&counts,cancelled,&cancel,debug?&timing:nullptr);
    if(env->ExceptionCheck())return nullptr;if(status!=SNP_OK)return error(env,snp_error_code(status));
    const auto start=debug?Clock::now():Clock::time_point{};
    auto config=locus_genotype_default_config();locus_genotype_result result{};
    if(locus_genotype_call(counts.bases,&config,&result)!=LOCUS_GENOTYPE_OK)return error(env,"INVALID_MODEL");
    const auto end=debug?Clock::now():Clock::time_point{};snp_stage_timing stages{};
    if(debug&&snp_split_timing(timing.query_ns,timing.io_ns,
       static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count()),
       static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(end-began).count()),&stages)!=SNP_OK)return error(env,"IO_ERROR");
    const std::string bases="ACGT";std::vector<int> order{static_cast<int>(bases.find(r.text[0]))};
    for(int b=0;b<4;b++)if(b!=order[0])order.push_back(b);
    int bi=0,bj=0;for(int i=0;i<4;i++){if(order[i]==result.best_i)bi=i;if(order[i]==result.best_j)bj=i;}
    if(bi>bj)std::swap(bi,bj);
    auto posteriorIndex=[](int i,int j){if(i>j)std::swap(i,j);return i*4-i*(i-1)/2+j-i;};
    std::ostringstream out;out.imbue(std::locale::classic());out<<std::setprecision(17);
    out<<"{\"total\":"<<counts.total<<",\"baseCounts\":[";
    for(int b=0;b<4;b++){if(b)out<<',';out<<counts.bases[order[b]];}
    out<<"],\"alleles\":[";for(int b=0;b<4;b++){if(b)out<<',';out<<'"'<<bases[order[b]]<<'"';}
    out<<"],\"ambiguous\":"<<counts.ambiguous<<",\"coverageOnly\":"<<counts.coverage_only
       <<",\"skippedBuckets\":"<<counts.skipped_buckets<<",\"effectiveDepth\":"<<result.effective_depth
       <<",\"posterior\":[";
    int k=0;for(int i=0;i<4;i++)for(int j=i;j<4;j++){if(k++)out<<',';out<<result.posterior[posteriorIndex(order[i],order[j])];}
    out<<"],\"bestGenotype\":["<<bi<<','<<bj<<"],\"bestPosterior\":"<<result.best_posterior
       <<",\"logScoreGap\":"<<result.log_score_gap<<",\"gt\":\"";
    if(result.called)out<<bi<<'/'<<bj;else out<<"./.";
    out<<"\",\"actualGenotype\":";
    if(result.called)out<<'"'<<bases[order[bi]]<<bases[order[bj]]<<'"';else out<<"null";
    out<<",\"noCallReason\":";if(result.no_call_reason)out<<'"'<<result.no_call_reason<<'"';else out<<"null";
    out<<",\"modelVersion\":\""<<result.model_version<<"\",\"calibrated\":false,\"parameters\":{\"epsilon\":"
       <<config.epsilon<<",\"rho\":"<<config.rho<<",\"priors\":[";
    for(int g=0;g<10;g++){if(g)out<<',';out<<config.priors[g];}
    out<<"],\"minDepth\":"<<config.min_depth<<",\"minPosterior\":"<<config.min_posterior<<'}';
    if(debug)out<<",\"debugTiming\":{\"ioMs\":"<<stages.io_ms<<",\"countMs\":"<<stages.count_ms
       <<",\"genotypeMs\":"<<stages.genotype_ms<<",\"nativeOverheadMs\":"<<stages.overhead_ms
       <<",\"nativeTotalMs\":"<<stages.total_ms<<'}';
    out<<'}';return env->NewStringUTF(out.str().c_str());
} catch(const std::bad_alloc&) {
    return env->ExceptionCheck()?nullptr:error(env,"RESOURCE_LIMIT");
} catch(...) { return env->ExceptionCheck()?nullptr:error(env,"IO_ERROR"); }
