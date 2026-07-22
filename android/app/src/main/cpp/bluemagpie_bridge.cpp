#include <jni.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "codec_lm.h"
#include "nlohmann/json.hpp"
#include "rn-completion.h"
#include "rn-llama.h"
#include "rn-tts.h"

#ifndef BLUEMAGPIE_RUNTIME_REVISION
#define BLUEMAGPIE_RUNTIME_REVISION "unknown"
#endif

namespace {

using json = nlohmann::ordered_json;
using clock_type = std::chrono::steady_clock;

std::mutex g_context_mutex;
std::unique_ptr<rnllama::llama_rn_context> g_context;
std::atomic<bool> g_cancelled{false};
std::atomic<uint64_t> g_active_request{0};

uint64_t request_hash(const std::string & value) {
    uint64_t hash = 1469598103934665603ULL;
    for (const unsigned char byte : value) {
        hash ^= byte;
        hash *= 1099511628211ULL;
    }
    return hash;
}

std::string from_jstring(JNIEnv * env, jstring value) {
    if (value == nullptr) return {};
    const char * chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

jstring to_jstring(JNIEnv * env, const json & value) {
    const std::string encoded = value.dump();
    return env->NewStringUTF(encoded.c_str());
}

int64_t elapsed_ms(clock_type::time_point start) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(clock_type::now() - start).count();
}

int64_t rss_bytes(const char * field = "VmRSS:") {
    std::ifstream status("/proc/self/status");
    std::string line;
    const std::string prefix(field);
    while (std::getline(status, line)) {
        if (line.rfind(prefix, 0) != 0) continue;
        const auto number_start = line.find_first_of("0123456789");
        if (number_start == std::string::npos) return 0;
        try {
            return std::stoll(line.substr(number_start)) * 1024;
        } catch (...) {
            return 0;
        }
    }
    return 0;
}

json failure(const char * code) {
    return {{"ok", false}, {"errorCode", code}};
}

bool write_wav_mono16(const std::string & path, const std::vector<float> & pcm, int sample_rate) {
    FILE * file = std::fopen(path.c_str(), "wb");
    if (file == nullptr) return false;
    const uint32_t samples = static_cast<uint32_t>(pcm.size());
    const uint16_t channels = 1;
    const uint16_t bits = 16;
    const uint32_t data_bytes = samples * 2;
    const uint32_t riff_bytes = 36 + data_bytes;
    const uint32_t byte_rate = static_cast<uint32_t>(sample_rate) * 2;
    const uint16_t block_align = 2;
    auto write32 = [&](uint32_t value) { return std::fwrite(&value, 4, 1, file) == 1; };
    auto write16 = [&](uint16_t value) { return std::fwrite(&value, 2, 1, file) == 1; };
    bool ok = std::fwrite("RIFF", 1, 4, file) == 4 && write32(riff_bytes) &&
        std::fwrite("WAVEfmt ", 1, 8, file) == 8 && write32(16) && write16(1) &&
        write16(channels) && write32(static_cast<uint32_t>(sample_rate)) &&
        write32(byte_rate) && write16(block_align) && write16(bits) &&
        std::fwrite("data", 1, 4, file) == 4 && write32(data_bytes);
    for (float sample : pcm) {
        if (!ok || !std::isfinite(sample)) { ok = false; break; }
        sample = std::max(-1.0f, std::min(1.0f, sample));
        const int16_t pcm16 = static_cast<int16_t>(std::lround(sample * 32767.0f));
        ok = std::fwrite(&pcm16, 2, 1, file) == 1;
    }
    ok = std::fclose(file) == 0 && ok;
    if (!ok) std::remove(path.c_str());
    return ok;
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_bluemagpie_BlueMagpieNativeBindings_nativeRuntimeRevision(
    JNIEnv * env,
    jobject /* receiver */) {
    return env->NewStringUTF(BLUEMAGPIE_RUNTIME_REVISION);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_bluemagpie_BlueMagpieNativeBindings_nativeInitializeJson(
    JNIEnv * env,
    jobject /* receiver */,
    jstring backbone_path_value,
    jstring codec_path_value,
    jstring backend_value) {
    const std::string backbone_path = from_jstring(env, backbone_path_value);
    const std::string codec_path = from_jstring(env, codec_path_value);
    const std::string backend = from_jstring(env, backend_value);
    if (backbone_path.empty() || codec_path.empty()) return to_jstring(env, failure("model_missing"));
    if (backend != "cpu") return to_jstring(env, failure("backend_unavailable"));

    std::lock_guard<std::mutex> lock(g_context_mutex);
    if (g_context != nullptr) {
        return to_jstring(env, {{"ok", true}, {"state", "ready"}, {"backend", "cpu"},
            {"elapsedMs", 0}, {"rssBeforeBytes", rss_bytes()}, {"rssAfterBytes", rss_bytes()}});
    }
    const auto started = clock_type::now();
    const int64_t before = rss_bytes();
    try {
        auto context = std::make_unique<rnllama::llama_rn_context>();
        common_params params;
        params.model.path = backbone_path;
        params.n_ctx = 4096;
        params.n_batch = 1024;
        params.embedding = true;
        const unsigned cores = std::thread::hardware_concurrency();
        params.cpuparams.n_threads = static_cast<int>(cores == 0 ? 4 : std::min(cores, 8U));
        params.n_gpu_layers = 0;
        params.no_kv_offload = true;
        if (!context->loadModel(params)) return to_jstring(env, failure("insufficient_memory"));
        if (!context->initVocoder(codec_path, -1, false)) return to_jstring(env, failure("decode_failed"));
        g_context = std::move(context);
        return to_jstring(env, {{"ok", true}, {"state", "ready"}, {"backend", "cpu"},
            {"elapsedMs", elapsed_ms(started)}, {"rssBeforeBytes", before},
            {"rssAfterBytes", rss_bytes()}});
    } catch (const std::bad_alloc &) {
        return to_jstring(env, failure("insufficient_memory"));
    } catch (...) {
        return to_jstring(env, failure("internal_error"));
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_bluemagpie_BlueMagpieNativeBindings_nativeSynthesizeJson(
    JNIEnv * env,
    jobject /* receiver */,
    jstring request_id_value,
    jstring text_value,
    jstring output_path_value) {
    const std::string request_id = from_jstring(env, request_id_value);
    const std::string text = from_jstring(env, text_value);
    const std::string output_path = from_jstring(env, output_path_value);
    if (request_id.empty() || text.empty() || output_path.empty()) {
        return to_jstring(env, failure("invalid_text"));
    }

    std::lock_guard<std::mutex> lock(g_context_mutex);
    if (g_context == nullptr || g_context->tts_wrapper == nullptr || g_context->completion == nullptr) {
        return to_jstring(env, failure("runtime_missing"));
    }
    const auto started = clock_type::now();
    g_cancelled.store(false);
    g_active_request.store(request_hash(request_id));
    auto finish = [&]() { g_active_request.store(0); };
    try {
        auto & context = *g_context;
        const auto formatted = context.tts_wrapper->getFormattedAudioCompletion(&context, "", text);
        if (formatted.flow != "continuous_embd") { finish(); return to_jstring(env, failure("decode_failed")); }
        context.params.prompt = formatted.prompt;
        context.params.n_predict = 500;
        context.params.embedding = true;
        context.params.sampling.temp = 0.7f;
        context.params.sampling.top_p = 0.9f;
        llama_set_embeddings(context.ctx, true);
        context.completion->rewind();
        if (!context.completion->initSampling()) { finish(); return to_jstring(env, failure("decode_failed")); }
        context.completion->loadPrompt({});
        context.completion->beginCompletion();

        int64_t first_audio_ms = -1;
        int steps = 0;
        while (context.completion->has_next_token && steps < context.params.n_predict) {
            if (g_cancelled.load()) break;
            (void) context.completion->doCompletion();
            ++steps;
            if (first_audio_ms < 0 && !context.tts_wrapper->audio_embeddings.empty()) {
                first_audio_ms = elapsed_ms(started);
            }
            if (context.tts_wrapper->audio_embeddings_done) break;
        }
        context.completion->endCompletion();
        if (g_cancelled.load()) {
            std::remove(output_path.c_str());
            finish();
            return to_jstring(env, failure("cancelled"));
        }
        if (context.tts_wrapper->audio_embeddings.empty() ||
            context.tts_wrapper->audio_embedding_dim <= 0) {
            finish();
            return to_jstring(env, failure("decode_failed"));
        }
        std::vector<float> pcm = context.tts_wrapper->decodeAudioEmbeddings(
            &context,
            context.tts_wrapper->audio_embeddings,
            context.tts_wrapper->audio_embedding_dim);
        const int sample_rate = context.tts_wrapper->getAudioSampleRate();
        if (pcm.empty() || sample_rate != 48000 || !write_wav_mono16(output_path, pcm, sample_rate)) {
            finish();
            return to_jstring(env, failure("io_failed"));
        }
        const int64_t total_ms = elapsed_ms(started);
        const int64_t samples = static_cast<int64_t>(pcm.size());
        finish();
        return to_jstring(env, {{"ok", true}, {"sampleRate", sample_rate}, {"samples", samples},
            {"durationMs", samples * 1000 / sample_rate},
            {"firstAudioMs", std::max<int64_t>(0, first_audio_ms)}, {"elapsedMs", total_ms},
            {"peakRssBytes", rss_bytes("VmHWM:")}});
    } catch (const std::bad_alloc &) {
        std::remove(output_path.c_str());
        finish();
        return to_jstring(env, failure("insufficient_memory"));
    } catch (...) {
        std::remove(output_path.c_str());
        finish();
        return to_jstring(env, failure("decode_failed"));
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_geneapp_bluemagpie_BlueMagpieNativeBindings_nativeCancel(
    JNIEnv * env,
    jobject /* receiver */,
    jstring request_id_value) {
    const std::string request_id = from_jstring(env, request_id_value);
    if (request_id.empty() || g_active_request.load() == request_hash(request_id)) {
        g_cancelled.store(true);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_geneapp_bluemagpie_BlueMagpieNativeBindings_nativeRelease(
    JNIEnv *,
    jobject /* receiver */) {
    g_cancelled.store(true);
    std::lock_guard<std::mutex> lock(g_context_mutex);
    g_context.reset();
    g_active_request.store(0);
}
