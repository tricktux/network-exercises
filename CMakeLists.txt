cmake_minimum_required(VERSION 3.21)

include(cmake/prelude.cmake)

project(
    network-exercises
    VERSION 0.1.0
    DESCRIPTION "Solve projects network-programming-exercises"
    HOMEPAGE_URL "https://example.com/"
    LANGUAGES C
)

include(cmake/variables.cmake)

# ---- Declare library ----

add_library(
    network-exercises_lib OBJECT
    source/lib.c
)

target_include_directories(
    network-exercises_lib ${warning_guard}
    PUBLIC
    "\$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/source>"
)

target_compile_features(network-exercises_lib PUBLIC c_std_23)

find_package(json-c REQUIRED)
target_link_libraries(network-exercises_lib PRIVATE json-c::json-c)

# Unfortunately, hedley provides no CMake package to be found trivially using
# find_package, so it has to be found manually
find_path(HEDLEY_INCLUDE_DIR hedley.h REQUIRED)
target_include_directories(
    network-exercises_lib SYSTEM
    PRIVATE "${HEDLEY_INCLUDE_DIR}"
)

# ---- Declare executable ----

add_executable(network-exercises_exe source/main.c)
add_executable(network-exercises::exe ALIAS network-exercises_exe)

set_property(TARGET network-exercises_exe PROPERTY OUTPUT_NAME network-exercises)

target_compile_features(network-exercises_exe PRIVATE c_std_23)

target_link_libraries(network-exercises_exe PRIVATE network-exercises_lib)

# ---- Install rules ----

if(NOT CMAKE_SKIP_INSTALL_RULES)
  include(cmake/install-rules.cmake)
endif()

# ---- Developer mode ----

if(NOT network-exercises_DEVELOPER_MODE)
  return()
elseif(NOT PROJECT_IS_TOP_LEVEL)
  message(
      AUTHOR_WARNING
      "Developer mode is intended for developers of network-exercises"
  )
endif()

include(cmake/dev-mode.cmake)
