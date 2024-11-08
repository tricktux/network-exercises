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

# ---- Declare executable ----

add_executable(network-exercises-exe 
    source/main.c
    source/log/log.c
)
add_executable(network-exercises::exe ALIAS network-exercises-exe)

set_property(TARGET network-exercises-exe PROPERTY OUTPUT_NAME network-exercises)

target_compile_features(network-exercises-exe PRIVATE c_std_23)

target_include_directories(network-exercises-exe PRIVATE 
    "${PROJECT_SOURCE_DIR}/source/log"
)

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
