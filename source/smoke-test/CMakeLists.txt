
add_executable(smoke-test
    "${PROJECT_SOURCE_DIR}/source/smoke-test/main.c"
    "${PROJECT_SOURCE_DIR}/source/log/log.c"
)

add_executable(network-exercises::smoke-test ALIAS smoke-test)

set_property(TARGET smoke-test PROPERTY OUTPUT_NAME smoke-test)

target_compile_features(smoke-test PRIVATE c_std_23)

target_include_directories(smoke-test PRIVATE 
    "${PROJECT_SOURCE_DIR}/source/log"
    "${PROJECT_SOURCE_DIR}/source/smoke-test"
)

