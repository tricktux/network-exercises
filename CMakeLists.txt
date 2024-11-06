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

add_executable(network-exercises_exe source/main.c)
add_executable(network-exercises::exe ALIAS network-exercises_exe)

set_property(TARGET network-exercises_exe PROPERTY OUTPUT_NAME network-exercises)

target_compile_features(network-exercises_exe PRIVATE c_std_23)

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
