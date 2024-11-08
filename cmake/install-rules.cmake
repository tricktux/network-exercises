install(
    TARGETS network-exercises-exe
    RUNTIME COMPONENT network-exercises_Runtime
)

if(PROJECT_IS_TOP_LEVEL)
  include(CPack)
endif()
