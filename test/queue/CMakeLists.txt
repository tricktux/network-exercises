
add_executable(queue-test 
    "${CMAKE_SOURCE_DIR}/source/utils/queue.c"
    "${CMAKE_SOURCE_DIR}/source/log/log.c"
    queue-test.cpp
)
target_link_libraries(
    queue-test PRIVATE
    Catch2::Catch2WithMain
)
target_include_directories(queue-test PRIVATE 
    "${CMAKE_SOURCE_DIR}/source"
)
target_compile_features(queue-test PRIVATE cxx_std_11)

catch_discover_tests(queue-test)

# Add a custom command to run tests as part of the regular build process
add_custom_command(
    TARGET queue-test
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E env CTEST_OUTPUT_ON_FAILURE=1 ${CMAKE_CTEST_COMMAND} -C $<CONFIG> --output-on-failure
    COMMENT "Running tests..."
)
