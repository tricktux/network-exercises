cmake_minimum_required(VERSION 3.21)

include(cmake/prelude.cmake)

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
