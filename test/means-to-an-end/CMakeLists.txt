
add_executable(messages-prices-test 
    "${CMAKE_SOURCE_DIR}/source/log/log.c"
    "${CMAKE_SOURCE_DIR}/source/means-to-an-end/asset-prices.c"
    messages-prices-test.cpp
)
target_link_libraries(
    messages-prices-test PRIVATE
    Catch2::Catch2WithMain
)
target_include_directories(messages-prices-test PRIVATE 
    "${CMAKE_SOURCE_DIR}/source"
)
target_compile_features(messages-prices-test PRIVATE cxx_std_11)

catch_discover_tests(messages-prices-test)

# Add a custom command to run tests as part of the regular build process
add_custom_command(
    TARGET messages-prices-test
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E env CTEST_OUTPUT_ON_FAILURE=1 ${CMAKE_CTEST_COMMAND} -C $<CONFIG> --output-on-failure
    COMMENT "Running tests..."
)

