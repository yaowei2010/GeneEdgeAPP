#include <jni.h>
#include <android/log.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "whisper.h"

#define TAG "GeneEdgeWhisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

namespace {

struct WavData {
    int sample_rate = 0;
    int channels = 0;
    int bits_per_sample = 0;
    std::vector<float> samples;
};

struct AbortState {
    std::chrono::steady_clock::time_point deadline;
};

bool abort_after_deadline(void *user_data) {
    const auto *state = static_cast<const AbortState *>(user_data);
    return state != nullptr && std::chrono::steady_clock::now() > state->deadline;
}

void log_progress(
        whisper_context * /* context */,
        whisper_state * /* state */,
        int progress,
        void * /* user_data */
) {
    LOGI("Offline ASR progress: %d%%", progress);
}

uint32_t read_u32_le(std::ifstream &in) {
    uint8_t bytes[4] = {};
    in.read(reinterpret_cast<char *>(bytes), 4);
    return static_cast<uint32_t>(bytes[0]) |
           (static_cast<uint32_t>(bytes[1]) << 8) |
           (static_cast<uint32_t>(bytes[2]) << 16) |
           (static_cast<uint32_t>(bytes[3]) << 24);
}

uint16_t read_u16_le(std::ifstream &in) {
    uint8_t bytes[2] = {};
    in.read(reinterpret_cast<char *>(bytes), 2);
    return static_cast<uint16_t>(bytes[0]) |
           (static_cast<uint16_t>(bytes[1]) << 8);
}

std::string read_fourcc(std::ifstream &in) {
    char id[4] = {};
    in.read(id, 4);
    return std::string(id, 4);
}

void skip_bytes(std::ifstream &in, uint32_t size) {
    in.seekg(size, std::ios::cur);
}

bool read_wav_file(const std::string &path, WavData &out, std::string &error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "Cannot open WAV file.";
        return false;
    }

    if (read_fourcc(in) != "RIFF") {
        error = "WAV file is missing RIFF header.";
        return false;
    }
    skip_bytes(in, 4);
    if (read_fourcc(in) != "WAVE") {
        error = "WAV file is missing WAVE header.";
        return false;
    }

    bool has_fmt = false;
    bool has_data = false;
    std::vector<int16_t> pcm;

    while (in && (!has_fmt || !has_data)) {
        const std::string chunk_id = read_fourcc(in);
        if (chunk_id.size() != 4 || !in) {
            break;
        }
        const uint32_t chunk_size = read_u32_le(in);

        if (chunk_id == "fmt ") {
            const uint16_t audio_format = read_u16_le(in);
            out.channels = read_u16_le(in);
            out.sample_rate = static_cast<int>(read_u32_le(in));
            skip_bytes(in, 6);
            out.bits_per_sample = read_u16_le(in);
            if (chunk_size > 16) {
                skip_bytes(in, chunk_size - 16);
            }
            if (audio_format != 1) {
                error = "Only PCM WAV is supported.";
                return false;
            }
            has_fmt = true;
        } else if (chunk_id == "data") {
            if (!has_fmt) {
                error = "WAV data chunk appeared before format chunk.";
                return false;
            }
            if (out.bits_per_sample != 16) {
                error = "Only 16-bit WAV is supported.";
                return false;
            }
            const size_t sample_count = chunk_size / sizeof(int16_t);
            pcm.resize(sample_count);
            in.read(reinterpret_cast<char *>(pcm.data()), static_cast<std::streamsize>(sample_count * sizeof(int16_t)));
            has_data = true;
        } else {
            skip_bytes(in, chunk_size);
        }

        if (chunk_size % 2 == 1) {
            skip_bytes(in, 1);
        }
    }

    if (!has_fmt || !has_data) {
        error = "WAV file is missing required chunks.";
        return false;
    }
    if (out.sample_rate != WHISPER_SAMPLE_RATE) {
        std::ostringstream oss;
        oss << "WAV sample rate must be " << WHISPER_SAMPLE_RATE << " Hz.";
        error = oss.str();
        return false;
    }
    if (out.channels != 1) {
        error = "Only mono WAV is supported.";
        return false;
    }

    out.samples.reserve(pcm.size());
    for (const int16_t value : pcm) {
        out.samples.push_back(static_cast<float>(value) / 32768.0f);
    }
    return true;
}

void throw_runtime(JNIEnv *env, const std::string &message) {
    jclass exception_class = env->FindClass("java/lang/RuntimeException");
    env->ThrowNew(exception_class, message.c_str());
}

std::string jstring_to_string(JNIEnv *env, jstring value) {
    const char *chars = env->GetStringUTFChars(value, nullptr);
    std::string result(chars == nullptr ? "" : chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_geneapp_MainActivity_nativeTranscribe(
        JNIEnv *env,
        jobject /* thiz */,
        jstring model_path,
        jstring wav_path
) {
    const std::string model = jstring_to_string(env, model_path);
    const std::string wav = jstring_to_string(env, wav_path);

    WavData audio;
    std::string error;
    if (!read_wav_file(wav, audio, error)) {
        throw_runtime(env, error);
        return nullptr;
    }

    LOGI("Loading ASR model with CPU fallback: %s", model.c_str());
    whisper_context_params context_params = whisper_context_default_params();
    context_params.use_gpu = false;
    context_params.gpu_device = 0;
    whisper_context *context = whisper_init_from_file_with_params(model.c_str(), context_params);
    if (context == nullptr) {
        throw_runtime(env, "Failed to load offline ASR model.");
        return nullptr;
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.translate = false;
    params.no_timestamps = true;
    params.language = "zh";
    params.no_context = true;
    params.single_segment = true;
    params.progress_callback = log_progress;
    AbortState abort_state{
            std::chrono::steady_clock::now() + std::chrono::seconds(30)
    };
    params.abort_callback = abort_after_deadline;
    params.abort_callback_user_data = &abort_state;

    const unsigned int cores = std::max(1u, std::thread::hardware_concurrency());
    params.n_threads = static_cast<int>(std::min(4u, cores));

    LOGI("Running offline ASR on %zu samples with %d CPU thread(s); GPU backend disabled for Pixel stability", audio.samples.size(), params.n_threads);
    const int transcribe_status = whisper_full(context, params, audio.samples.data(), static_cast<int>(audio.samples.size()));
    if (transcribe_status != 0) {
        whisper_free(context);
        throw_runtime(env, "Offline ASR transcription failed or timed out after 30 seconds.");
        return nullptr;
    }

    std::ostringstream text;
    const int segments = whisper_full_n_segments(context);
    for (int i = 0; i < segments; ++i) {
        const char *segment = whisper_full_get_segment_text(context, i);
        if (segment != nullptr) {
            text << segment;
        }
    }

    whisper_free(context);
    LOGI("Offline ASR completed with %d segment(s)", segments);
    return env->NewStringUTF(text.str().c_str());
}
