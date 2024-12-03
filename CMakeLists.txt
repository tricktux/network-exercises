cmake_minimum_required(VERSION 3.21)

include(cmake/prelude.cmake)

if (ZIG)
    set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cmake/zig-toolchain.cmake")
endif()

project(
    network-exercises
    VERSION 0.1.0
    DESCRIPTION "Solution for protohackers server programming exercises"
    HOMEPAGE_URL "https://github.com/tricktux/network-exercises"
    LANGUAGES C
)

include(cmake/variables.cmake)

# ---- Declare executable ----

add_subdirectory(source/smoke-test)
add_subdirectory(source/prime-time)
add_subdirectory(source/means-to-an-end)

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
