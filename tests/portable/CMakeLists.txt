cmake_minimum_required(VERSION 3.20)
project(bridge_portable_contract LANGUAGES CXX)

enable_testing()
add_executable(bridge_portable_contract
  ../contract_tests.cpp
  ../../src/bridge_contract.cpp
  ../../src/gzip_stored.cpp
)
target_compile_features(bridge_portable_contract PRIVATE cxx_std_20)
if(MSVC)
  target_compile_options(bridge_portable_contract PRIVATE /W4 /WX /UNDEBUG)
else()
  # Release builds normally define NDEBUG; all contract assertions must run.
  # Deliberately undefine it so CTest cannot accidentally report false PASS.
  target_compile_options(bridge_portable_contract PRIVATE -Wall -Wextra -Werror -UNDEBUG)
endif()
add_test(NAME schema_v3_cue_subsong_fingerprints_and_gzip_invariants
  COMMAND bridge_portable_contract)
set_tests_properties(schema_v3_cue_subsong_fingerprints_and_gzip_invariants
  PROPERTIES WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../..")
