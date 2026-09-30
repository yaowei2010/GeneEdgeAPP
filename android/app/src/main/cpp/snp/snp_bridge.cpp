#include <jni.h>
#include <unistd.h>
#include <sstream>
#include <iomanip>
#include <locale>
#include <new>
#include <chrono>
#include "snp_engine.h"
#include "snp_timing.h"
#include "genotype_model.h"

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
