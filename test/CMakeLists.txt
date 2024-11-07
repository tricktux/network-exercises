# Parent project does not export its library target, so this CML implicitly
# depends on being added from it, i.e. the testing is done only from the build
# tree and is not feasible from an install location

project(network-exercisesTests LANGUAGES CXX)

# ---- Dependencies ----

find_package(Catch2 REQUIRED)
include(Catch)

# ---- Tests ----

add_executable(network-exercises_test source/network-exercises_test.cpp)
target_link_libraries(
    network-exercises_test PRIVATE
    # network-exercises_lib
    Catch2::Catch2WithMain
)
target_compile_features(network-exercises_test PRIVATE cxx_std_11)

catch_discover_tests(network-exercises_test)

# ---- End-of-file commands ----

add_folders(Test)
