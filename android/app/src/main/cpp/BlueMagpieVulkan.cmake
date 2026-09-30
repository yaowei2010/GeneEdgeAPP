include(ExternalProject)

function(_geneedge_prefix_ggml_source input output)
    file(READ "${input}" content)
    string(REPLACE "GGML_" "LM_GGML_" content "${content}")
    string(REPLACE "ggml_" "lm_ggml_" content "${content}")
    string(REPLACE "GGUF_" "LM_GGUF_" content "${content}")
    string(REPLACE "gguf_" "lm_gguf_" content "${content}")
    if(content MATCHES "Compute pipeline creation failed for")
        set(content "#include <android/log.h>\n${content}")
        string(REPLACE
            "const bool use_subgroups = device->subgroup_arithmetic && device->architecture != vk_device_architecture::AMD_GCN;"
            "const bool use_subgroups = device->subgroup_arithmetic && device->architecture != vk_device_architecture::AMD_GCN && getenv(\"GGML_VK_DISABLE_SUBGROUP_REDUCTIONS\") == nullptr;"
            content "${content}")
        string(REPLACE
            "std::cerr << \"lm_ggml_vulkan: Compute pipeline creation failed for \" << pipeline->name << std::endl;"
            "__android_log_print(ANDROID_LOG_ERROR, \"GeneEdgeBlueMagpie\", \"Vulkan pipeline=%s failed: %s\", pipeline->name.c_str(), e.what());\n        std::cerr << \"lm_ggml_vulkan: Compute pipeline creation failed for \" << pipeline->name << std::endl;"
            content "${content}")
    endif()
    if(EXISTS "${output}")
        file(READ "${output}" previous_content)
        if(previous_content STREQUAL content)
            return()
        endif()
    endif()
    file(WRITE "${output}" "${content}")
endfunction()

function(geneedge_apply_bluemagpie_model_profile target runtime_dir)
    set(input "${runtime_dir}/cpp/rn-tts.cpp")
    set(output_dir "${CMAKE_CURRENT_BINARY_DIR}/bluemagpie-profile")
    set(output "${output_dir}/rn-tts.cpp")
    file(MAKE_DIRECTORY "${output_dir}")
    file(READ "${input}" content)
    string(REPLACE
        "const float   cfg_value   = 2.8f;"
        "const float   cfg_value   = 1.5f;"
        content "${content}")
    string(REPLACE
        "const int32_t n_timesteps = 9;"
        "const int32_t n_timesteps = 20;"
        content "${content}")
    string(REPLACE
        "// BlueMagpie official release defaults (models/bluemagpie\n    // release_metadata.json on the upstream HF repo): guidance_scale = 2.8,\n    // num_timesteps = 9.  These replace the earlier VoxCPM-style 2.0/10."
        "// GeneEdge Android stability experiment: use moderate classifier-free\n    // guidance for stronger text adherence without the 2.0 profile's observed\n    // device distortion, plus 20 CFM integration steps."
        content "${content}")
    if(content STREQUAL "")
        message(FATAL_ERROR "Failed to read BlueMagpie rn-tts.cpp")
    endif()
    if(content MATCHES "cfg_value   = 2\\.8f" OR content MATCHES "n_timesteps = 9")
        message(FATAL_ERROR "Failed to apply the pinned BlueMagpie model profile")
    endif()
    if(EXISTS "${output}")
        file(READ "${output}" previous_content)
    endif()
    if(NOT EXISTS "${output}" OR NOT previous_content STREQUAL content)
        file(WRITE "${output}" "${content}")
    endif()

    get_target_property(target_sources_list ${target} SOURCES)
    list(FILTER target_sources_list EXCLUDE REGEX "/rn-tts\\.cpp$")
    set_property(TARGET ${target} PROPERTY SOURCES "${target_sources_list}")
    target_sources(${target} PRIVATE "${output}")
endfunction()

function(geneedge_enable_bluemagpie_vulkan target runtime_dir)
    set(llama_dir "${runtime_dir}/third_party/llama.cpp")
    set(vulkan_dir "${llama_dir}/ggml/src/ggml-vulkan")
    set(vulkan_header "${llama_dir}/ggml/include/ggml-vulkan.h")
    if(NOT EXISTS "${vulkan_dir}/ggml-vulkan.cpp" OR NOT EXISTS "${vulkan_header}")
        message(FATAL_ERROR
            "Pinned llama.cpp Vulkan source is missing. Run: "
            "git -C third_party/llama.rn-codec submodule update --init third_party/llama.cpp"
        )
    endif()

    set(generated_dir "${CMAKE_CURRENT_BINARY_DIR}/bluemagpie-vulkan")
    file(MAKE_DIRECTORY "${generated_dir}")
    set(prefixed_cpp "${generated_dir}/ggml-vulkan.cpp")
    set(prefixed_header "${generated_dir}/ggml-vulkan.h")
    _geneedge_prefix_ggml_source("${vulkan_dir}/ggml-vulkan.cpp" "${prefixed_cpp}")
    _geneedge_prefix_ggml_source("${vulkan_header}" "${prefixed_header}")

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        # find_program inherits the Android toolchain search paths and can pick
        # NDK clang. The shader generator must be executable on the build host.
        set(host_c_compiler "/usr/bin/clang")
        set(host_cxx_compiler "/usr/bin/clang++")
        set(glslc_host_tag "darwin-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        find_program(host_c_compiler NAMES clang gcc REQUIRED NO_CMAKE_FIND_ROOT_PATH)
        find_program(host_cxx_compiler NAMES clang++ g++ REQUIRED NO_CMAKE_FIND_ROOT_PATH)
        set(glslc_host_tag "linux-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        find_program(host_c_compiler NAMES clang gcc cl REQUIRED NO_CMAKE_FIND_ROOT_PATH)
        find_program(host_cxx_compiler NAMES clang++ g++ cl REQUIRED NO_CMAKE_FIND_ROOT_PATH)
        set(glslc_host_tag "windows-x86_64")
    else()
        message(FATAL_ERROR "Unsupported Vulkan shader build host: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    if(NOT EXISTS "${host_c_compiler}" OR NOT EXISTS "${host_cxx_compiler}")
        message(FATAL_ERROR "BlueMagpie Vulkan host compiler is unavailable")
    endif()
    set(shader_source_dir "${vulkan_dir}/vulkan-shaders")
    set(shader_host_dir "${generated_dir}/host")
    ExternalProject_Add(
        bluemagpie-vulkan-shaders-gen
        SOURCE_DIR "${shader_source_dir}"
        CMAKE_ARGS
            -DCMAKE_INSTALL_PREFIX=${shader_host_dir}
            -DCMAKE_INSTALL_BINDIR=.
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_C_COMPILER=${host_c_compiler}
            -DCMAKE_CXX_COMPILER=${host_cxx_compiler}
            -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=NEVER
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=NEVER
        BUILD_COMMAND ${CMAKE_COMMAND} --build . --config Release
        INSTALL_COMMAND ${CMAKE_COMMAND} --install . --config Release
        BUILD_ALWAYS FALSE
        BUILD_BYPRODUCTS "${shader_host_dir}/vulkan-shaders-gen"
    )

    set(shader_generator "${shader_host_dir}/vulkan-shaders-gen")
    set(shader_header "${generated_dir}/ggml-vulkan-shaders.hpp")
    set(shader_spv_dir "${generated_dir}/spv")
    file(GLOB shader_files CONFIGURE_DEPENDS "${shader_source_dir}/*.comp")
    file(GLOB shader_generator_sources CONFIGURE_DEPENDS
        "${shader_source_dir}/*.cpp"
        "${shader_source_dir}/*.h"
    )
    add_custom_command(
        OUTPUT "${shader_header}"
        COMMAND "${shader_generator}"
            --output-dir "${shader_spv_dir}"
            --target-hpp "${shader_header}"
        DEPENDS ${shader_generator_sources} "${shader_generator}"
        COMMENT "Generate BlueMagpie Vulkan shader registry"
    )

    set(shader_cpp_files "")
    foreach(shader_file ${shader_files})
        get_filename_component(shader_name "${shader_file}" NAME)
        set(shader_cpp "${generated_dir}/${shader_name}.cpp")
        add_custom_command(
            OUTPUT "${shader_cpp}"
            DEPFILE "${shader_cpp}.d"
            COMMAND "${shader_generator}"
                --glslc "${CMAKE_ANDROID_NDK}/shader-tools/${glslc_host_tag}/glslc"
                --source "${shader_file}"
                --output-dir "${shader_spv_dir}"
                --target-hpp "${shader_header}"
                --target-cpp "${shader_cpp}"
            DEPENDS "${shader_file}" ${shader_generator_sources} "${shader_generator}"
            COMMENT "Compile BlueMagpie Vulkan shader ${shader_name}"
        )
        list(APPEND shader_cpp_files "${shader_cpp}")
    endforeach()

    find_library(vulkan_library vulkan REQUIRED)
    # Keep generated sources and their custom commands in this directory.
    # Passing them directly to rnllama (declared in another directory) makes
    # CMake create empty GENERATED placeholders and drops the commands.
    add_library(bluemagpie_vulkan_backend OBJECT
        "${prefixed_cpp}"
        "${prefixed_header}"
        "${shader_header}"
        ${shader_cpp_files}
    )
    add_dependencies(bluemagpie_vulkan_backend bluemagpie-vulkan-shaders-gen)
    set_target_properties(bluemagpie_vulkan_backend PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
    )
    target_include_directories(bluemagpie_vulkan_backend PRIVATE
        "${generated_dir}"
        "${runtime_dir}/cpp"
        "${runtime_dir}/cpp/ggml-cpu"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/Vulkan-Headers/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/spirv-headers/include"
    )
    target_compile_definitions(bluemagpie_vulkan_backend PRIVATE
        LM_GGML_USE_VULKAN
        VK_USE_PLATFORM_ANDROID_KHR
    )
    target_include_directories(${target} PRIVATE "${generated_dir}")
    target_compile_definitions(${target} PRIVATE LM_GGML_USE_VULKAN VK_USE_PLATFORM_ANDROID_KHR)
    target_sources(${target} PRIVATE $<TARGET_OBJECTS:bluemagpie_vulkan_backend>)
    target_link_libraries(${target} PRIVATE "${vulkan_library}")
endfunction()
