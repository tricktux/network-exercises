
add_executable(smoke-test
    "${PROJECT_SOURCE_DIR}/source/smoke-test/main.c"
    "${PROJECT_SOURCE_DIR}/source/utils/epoll.c"
    "${PROJECT_SOURCE_DIR}/source/log/log.c"
    "${PROJECT_SOURCE_DIR}/source/thpool/thpool.c"
    "${PROJECT_SOURCE_DIR}/source/utils/utils.c"
    "${PROJECT_SOURCE_DIR}/source/utils/queue.c"
    "${PROJECT_SOURCE_DIR}/source/utils/sockets.c"
)

add_executable(network-exercises::smoke-test ALIAS smoke-test)

set_property(TARGET smoke-test PROPERTY OUTPUT_NAME smoke-test)

target_compile_definitions(smoke-test PUBLIC LOG_USE_COLOR=1)

target_compile_features(smoke-test PRIVATE c_std_23)

target_include_directories(smoke-test PRIVATE 
    "${PROJECT_SOURCE_DIR}/source"
)

