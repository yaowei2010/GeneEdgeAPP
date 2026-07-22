set(_spirv_headers_root "${CMAKE_ANDROID_NDK}/sources/third_party/shaderc/third_party/glslang/SPIRV")

if(NOT EXISTS "${_spirv_headers_root}/spirv.hpp")
    message(FATAL_ERROR "Android NDK SPIR-V headers not found at ${_spirv_headers_root}")
endif()

if(NOT TARGET SPIRV-Headers::SPIRV-Headers)
    add_library(SPIRV-Headers::SPIRV-Headers INTERFACE IMPORTED)
    set_target_properties(
        SPIRV-Headers::SPIRV-Headers
        PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${_spirv_headers_root}"
    )
endif()

set(SPIRV-Headers_FOUND TRUE)
