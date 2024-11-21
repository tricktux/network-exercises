# Parent project does not export its library target, so this CML implicitly
# depends on being added from it, i.e. the testing is done only from the build
# tree and is not feasible from an install location

project(network-exercises-tests LANGUAGES CXX)

# ---- Dependencies ----

find_package(Catch2 REQUIRED)
include(Catch)

# ---- Tests ----

add_executable(utils-test 
    "${CMAKE_SOURCE_DIR}/source/utils/queue.c"
    "${CMAKE_SOURCE_DIR}/source/log/log.c"
    source/queue-test.cpp
)
target_link_libraries(
    utils-test PRIVATE
    Catch2::Catch2WithMain
)
target_include_directories(utils-test PRIVATE 
    "${CMAKE_SOURCE_DIR}/source"
)
target_compile_features(utils-test PRIVATE cxx_std_11)

catch_discover_tests(utils-test)

# ---- End-of-file commands ----

add_folders(Test)
