include_guard()

if(CMAKE_GENERATOR MATCHES "Visual Studio")
    message(FATAL_ERROR "Visual Studio generator not supported, use: cmake -G Ninja")
endif()

message(STATUS "ZIG_TARGET: ${ZIG_TARGET}")

if(NOT ${ZIG_TARGET} MATCHES "^([a-zA-Z0-9_]+)-([a-zA-Z0-9_]+)-([a-zA-Z0-9_]+)(\.(.*))?$")
    message(SEND_ERROR "Expected -DZIG_TARGET=<arch>-<os>-<abi>[.<glibc_version>]")
endif()

set(ZIG_ARCH ${CMAKE_MATCH_1})
set(ZIG_OS ${CMAKE_MATCH_2})
set(ZIG_ABI ${CMAKE_MATCH_3})
set(ZIG_GLIBC ${CMAKE_MATCH_5})

message(STATUS "ZIG_ARCH: ${ZIG_ARCH}")
message(STATUS "ZIG_OS: ${ZIG_OS}")
message(STATUS "ZIG_ABI: ${ZIG_ABI}")
message(STATUS "ZIG_GLIBC: ${ZIG_GLIBC}")

if(ZIG_OS STREQUAL "linux")
    set(CMAKE_SYSTEM_NAME "Linux")
elseif(ZIG_OS STREQUAL "windows")
    set(CMAKE_SYSTEM_NAME "Windows")
elseif(ZIG_OS STREQUAL "macos")
    set(CMAKE_SYSTEM_NAME "Darwin")
elseif(ZIG_OS STREQUAL "freestanding")
    set(CMAKE_SYSTEM_NAME "Generic")
elseif(ZIG_OS STREQUAL "uefi")
    set(CMAKE_SYSTEM_NAME "UEFI")
    # Fix compiler detection (lld-link: error: <root>: undefined symbol: EfiMain)
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
else()
    # NOTE: If this happens, add a new case with one of the following system names:
    # https://cmake.org/cmake/help/latest/variable/CMAKE_SYSTEM_NAME.html#system-names-known-to-cmake
    message(AUTHOR_WARNING "Unknown OS: ${ZIG_OS}")
endif()

set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR ${ZIG_ARCH})

set(CMAKE_C_COMPILER zig cc)
set(CMAKE_CXX_COMPILER zig c++)
set(CMAKE_C_COMPILER_TARGET ${ZIG_TARGET})
set(CMAKE_CXX_COMPILER_TARGET ${ZIG_TARGET})

message(STATUS "CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
message(STATUS "CMAKE_SYSTEM_PROCESSOR: ${CMAKE_SYSTEM_PROCESSOR}")

if(WIN32)
    set(SCRIPT_SUFFIX ".cmd")
else()
    set(SCRIPT_SUFFIX ".sh")
endif()

# This is working (thanks to Simon for finding this trick)
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/zig-ar${SCRIPT_SUFFIX}")
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/zig-ranlib${SCRIPT_SUFFIX}")
set(CMAKE_RC_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig-rc${SCRIPT_SUFFIX}")

# Add custom UEFI platform to module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
