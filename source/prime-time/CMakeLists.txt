
set(PROJECT_NAME "prime-time")

add_executable(${PROJECT_NAME}
    "${PROJECT_SOURCE_DIR}/source/${PROJECT_NAME}/main.c"
    # "${PROJECT_SOURCE_DIR}/source/smoke-test/epoll.c"
    "${PROJECT_SOURCE_DIR}/source/log/log.c"
    # "${PROJECT_SOURCE_DIR}/source/thpool/thpool.c"
)

add_executable(network-exercises::${PROJECT_NAME} ALIAS ${PROJECT_NAME})

set_property(TARGET ${PROJECT_NAME} PROPERTY OUTPUT_NAME ${PROJECT_NAME})

target_compile_definitions(${PROJECT_NAME} PUBLIC LOG_USE_COLOR=1)

target_compile_features(${PROJECT_NAME} PRIVATE c_std_23)

target_include_directories(${PROJECT_NAME} PRIVATE 
    "${PROJECT_SOURCE_DIR}/source"
)

