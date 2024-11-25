
add_executable(is-prime-test 
    "${CMAKE_SOURCE_DIR}/source/log/log.c"
    "${CMAKE_SOURCE_DIR}/source/prime-time/is-prime-request.c"
    is-prime-request-test.cpp
)
target_link_libraries(
    is-prime-test PRIVATE
    Catch2::Catch2WithMain
    json-c::json-c
)
target_include_directories(is-prime-test PRIVATE 
    "${CMAKE_SOURCE_DIR}/source"
)
target_compile_features(is-prime-test PRIVATE cxx_std_11)

catch_discover_tests(is-prime-test)

# Add a custom command to run tests as part of the regular build process
add_custom_command(
    TARGET is-prime-test
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E env CTEST_OUTPUT_ON_FAILURE=1 ${CMAKE_CTEST_COMMAND} -C $<CONFIG> --output-on-failure
    COMMENT "Running tests..."
)

