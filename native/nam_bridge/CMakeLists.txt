# Minimal native bridge over the vendored NeuralAmpModelerCore, for the
# WyrmTone V4a Windows inference proof. Not a product build script: this is
# invoked directly with CMake (see README.md in this folder), independent of
# Flutter's own build. Android wiring is a separate, later milestone.
cmake_minimum_required(VERSION 3.20)
project(wyrmtone_nam_bridge CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (MSVC)
  add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
endif()

set(NAM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/NeuralAmpModelerCore")
if (NOT EXISTS "${NAM_ROOT}/NAM/dsp.h")
  message(FATAL_ERROR "NeuralAmpModelerCore not found at ${NAM_ROOT}. See "
                       "docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md (V4) for the pinned revision to fetch.")
endif()

file(GLOB NAM_SOURCES "${NAM_ROOT}/NAM/*.cpp" "${NAM_ROOT}/NAM/wavenet/*.cpp")

add_library(wyrmtone_nam SHARED
  src/wyrmtone_nam.cpp
  ${NAM_SOURCES}
)
target_include_directories(wyrmtone_nam PRIVATE
  include
  "${NAM_ROOT}"
  "${NAM_ROOT}/Dependencies/eigen"
  "${NAM_ROOT}/Dependencies/nlohmann"
)
target_compile_definitions(wyrmtone_nam PRIVATE NAM_ENABLE_A2_FAST)

# Small native console runner for the smoke tests (loads a real .nam, no
# Dart/FFI involved) — the "native runner" the V4a smoke tests are compared
# against. Linked against the same sources as the DLL (not against the DLL
# itself), so it is a fully independent instance of the same code.
add_executable(nam_bridge_runner tools/nam_bridge_runner.cpp ${NAM_SOURCES})
target_include_directories(nam_bridge_runner PRIVATE
  include
  "${NAM_ROOT}"
  "${NAM_ROOT}/Dependencies/eigen"
  "${NAM_ROOT}/Dependencies/nlohmann"
)
target_compile_definitions(nam_bridge_runner PRIVATE NAM_ENABLE_A2_FAST)
target_sources(nam_bridge_runner PRIVATE src/wyrmtone_nam.cpp)
