# Parent project does not export its library target, so this CML implicitly
# depends on being added from it, i.e. the testing is done only from the build
# tree and is not feasible from an install location

# Enable test functionalities
enable_testing()

project(network-exercises-tests LANGUAGES C CXX)

# ---- Dependencies ----

find_package(Catch2 REQUIRED)
find_package(json-c CONFIG REQUIRED)
include(Catch)

# ---- Tests ----

add_subdirectory(queue)
add_subdirectory(is-prime)
add_subdirectory(means-to-an-end)
add_subdirectory(budget-chat)

# ---- End-of-file commands ----

add_folders(Test)
