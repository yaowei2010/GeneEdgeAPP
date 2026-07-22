cmake_minimum_required(VERSION 3.10)

project(geneedge_whisper)

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
