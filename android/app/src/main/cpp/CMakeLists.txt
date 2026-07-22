cmake_minimum_required(VERSION 3.10)

project(geneedge_whisper)

option(
    GENEEDGE_BLUEMAGPIE_POC
    "Compile the Android-only BlueMagpie diagnostic runtime"
    OFF
)

message(STATUS "GeneEdge BlueMagpie PoC enabled: ${GENEEDGE_BLUEMAGPIE_POC}")

set(
    BLUEMAGPIE_RUNTIME_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.rn-codec"
)
set(
    BLUEMAGPIE_RUNTIME_REVISION
    "7d5cf82cf33883bc80ec845905f5d85c5565d132"
)

if(GENEEDGE_BLUEMAGPIE_POC)
    if(NOT EXISTS "${BLUEMAGPIE_RUNTIME_DIR}/cpp/rn-tts.cpp" OR
       NOT EXISTS "${BLUEMAGPIE_RUNTIME_DIR}/cpp/codec/src/codec.cpp")
        message(FATAL_ERROR
            "BlueMagpie codec source is missing. Run: git submodule update --init third_party/llama.rn-codec"
        )
    endif()
    message(STATUS "BlueMagpie runtime revision: ${BLUEMAGPIE_RUNTIME_REVISION}")
    message(STATUS "BlueMagpie dependency boundary: C++ only (no React Native/JSI)")

    add_library(
        geneedge_bluemagpie
        SHARED
        bluemagpie_bridge.cpp
    )
    target_compile_definitions(
        geneedge_bluemagpie
        PRIVATE
        BLUEMAGPIE_RUNTIME_REVISION="${BLUEMAGPIE_RUNTIME_REVISION}"
    )
    target_compile_options(
        geneedge_bluemagpie
        PRIVATE
        -O3
        -fvisibility=hidden
        -fvisibility-inlines-hidden
    )
    target_link_options(
        geneedge_bluemagpie
        PRIVATE
        -Wl,--exclude-libs,ALL
        -Wl,--gc-sections
    )

    # The upstream RN wrapper builds several CPU-tuned variants when it sees
    # ANDROID_ABI. Clear it only while adding its C++ runtime so the PoC builds
    # one generic ARM64 runtime and never pulls the React/JSI JNI target.
    set(_GENEEDGE_ANDROID_ABI "${ANDROID_ABI}")
    set(ANDROID_ABI "")
    add_subdirectory(
        "${BLUEMAGPIE_RUNTIME_DIR}/android/src/main/rnllama"
        "${CMAKE_CURRENT_BINARY_DIR}/bluemagpie-rnllama"
        EXCLUDE_FROM_ALL
    )
    set(ANDROID_ABI "${_GENEEDGE_ANDROID_ABI}")
    unset(_GENEEDGE_ANDROID_ABI)

    # The pinned codec branch references its WAV utility from tts_runner but
    # the upstream Android glob omits the nested common/utils directory.
    target_sources(
        rnllama
        PRIVATE
        "${BLUEMAGPIE_RUNTIME_DIR}/cpp/codec/common/utils/wav_io.cpp"
    )
    target_include_directories(
        rnllama
        PRIVATE
        "${BLUEMAGPIE_RUNTIME_DIR}/cpp/codec/common/utils"
    )

    target_include_directories(
        geneedge_bluemagpie
        PRIVATE
        "${BLUEMAGPIE_RUNTIME_DIR}/cpp"
        "${BLUEMAGPIE_RUNTIME_DIR}/cpp/common"
        "${BLUEMAGPIE_RUNTIME_DIR}/cpp/codec/include"
    )
    target_link_libraries(geneedge_bluemagpie PRIVATE rnllama android log)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(WHISPER_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/whisper.cpp)
set(VULKAN_HEADERS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/Vulkan-Headers)

include_directories(${VULKAN_HEADERS_DIR}/include)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/spirv-headers/include)

file(READ "${WHISPER_LIB_DIR}/CMakeLists.txt" MAIN_CMAKE_CONTENT)
string(REGEX MATCH "project\\(\"whisper\\.cpp\" VERSION ([0-9]+\\.[0-9]+\\.[0-9]+)\\)" VERSION_MATCH "${MAIN_CMAKE_CONTENT}")
if(CMAKE_MATCH_1)
    set(WHISPER_VERSION ${CMAKE_MATCH_1})
else()
    set(WHISPER_VERSION "unknown")
endif()

find_library(LOG_LIB log)
find_library(VULKAN_LIB vulkan)

list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set(SPIRV-Headers_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cmake/SPIRV-Headers" CACHE PATH "SPIRV-Headers config path" FORCE)
set(Vulkan_GLSLC_EXECUTABLE "${CMAKE_ANDROID_NDK}/shader-tools/darwin-x86_64/glslc" CACHE FILEPATH "Android NDK glslc" FORCE)

include(FetchContent)
set(GGML_VULKAN ON CACHE BOOL "Enable ggml Vulkan backend" FORCE)
set(GGML_VULKAN_RUN_TESTS OFF CACHE BOOL "Disable Vulkan backend tests" FORCE)
set(GGML_VULKAN_CHECK_RESULTS OFF CACHE BOOL "Disable Vulkan result checks" FORCE)
FetchContent_Declare(ggml SOURCE_DIR ${WHISPER_LIB_DIR}/ggml)
FetchContent_MakeAvailable(ggml)

add_library(
    geneedge_whisper
    SHARED
    geneedge_whisper_jni.cpp
    ${WHISPER_LIB_DIR}/src/whisper.cpp
)

target_compile_definitions(geneedge_whisper PUBLIC GGML_USE_CPU)
target_compile_definitions(geneedge_whisper PRIVATE WHISPER_VERSION="${WHISPER_VERSION}")
target_compile_options(geneedge_whisper PRIVATE -O3 -fvisibility=hidden -fvisibility-inlines-hidden)

target_include_directories(
    geneedge_whisper
    PRIVATE
    ${WHISPER_LIB_DIR}
    ${WHISPER_LIB_DIR}/include
    ${WHISPER_LIB_DIR}/src
    ${WHISPER_LIB_DIR}/ggml/include
    ${WHISPER_LIB_DIR}/ggml/src
    ${WHISPER_LIB_DIR}/ggml/src/ggml-cpu
    ${WHISPER_LIB_DIR}/ggml/src/ggml-vulkan
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/Vulkan-Headers/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/spirv-headers/include
)

target_link_libraries(geneedge_whisper ${LOG_LIB} android ${VULKAN_LIB} ggml)
