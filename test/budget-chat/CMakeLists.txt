
add_executable(budget-chat-client-test 
    "${CMAKE_SOURCE_DIR}/source/log/log.c"
    "${CMAKE_SOURCE_DIR}/source/utils/queue.c"
    "${CMAKE_SOURCE_DIR}/source/utils/sockets.c"
    "${CMAKE_SOURCE_DIR}/source/budget-chat/client.c"
    client-test.cpp
)
target_link_libraries(
    budget-chat-client-test PRIVATE
    Catch2::Catch2WithMain
)
target_include_directories(budget-chat-client-test PRIVATE 
    "${CMAKE_SOURCE_DIR}/source"
)
target_compile_features(budget-chat-client-test PRIVATE cxx_std_11)

catch_discover_tests(budget-chat-client-test)

# Add a custom command to run tests as part of the regular build process
add_custom_command(
    TARGET budget-chat-client-test
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E env CTEST_OUTPUT_ON_FAILURE=1 ${CMAKE_CTEST_COMMAND} -C $<CONFIG> --output-on-failure
    COMMENT "Running tests..."
)

