include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(TextEditor_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(TextEditor_setup_options)
  option(TextEditor_ENABLE_HARDENING "Enable hardening" ON)
  option(TextEditor_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    TextEditor_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    TextEditor_ENABLE_HARDENING
    OFF)

  TextEditor_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR TextEditor_PACKAGING_MAINTAINER_MODE)
    option(TextEditor_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(TextEditor_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(TextEditor_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TextEditor_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TextEditor_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TextEditor_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(TextEditor_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(TextEditor_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TextEditor_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(TextEditor_ENABLE_IPO "Enable IPO/LTO" ON)
    option(TextEditor_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(TextEditor_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TextEditor_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(TextEditor_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(TextEditor_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TextEditor_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TextEditor_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TextEditor_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(TextEditor_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(TextEditor_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TextEditor_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      TextEditor_ENABLE_IPO
      TextEditor_WARNINGS_AS_ERRORS
      TextEditor_ENABLE_USER_LINKER
      TextEditor_ENABLE_SANITIZER_ADDRESS
      TextEditor_ENABLE_SANITIZER_LEAK
      TextEditor_ENABLE_SANITIZER_UNDEFINED
      TextEditor_ENABLE_SANITIZER_THREAD
      TextEditor_ENABLE_SANITIZER_MEMORY
      TextEditor_ENABLE_UNITY_BUILD
      TextEditor_ENABLE_CLANG_TIDY
      TextEditor_ENABLE_CPPCHECK
      TextEditor_ENABLE_COVERAGE
      TextEditor_ENABLE_PCH
      TextEditor_ENABLE_CACHE)
  endif()

  TextEditor_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (TextEditor_ENABLE_SANITIZER_ADDRESS OR TextEditor_ENABLE_SANITIZER_THREAD OR TextEditor_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(TextEditor_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(TextEditor_global_options)
  if(TextEditor_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    TextEditor_enable_ipo()
  endif()

  TextEditor_supports_sanitizers()

  if(TextEditor_ENABLE_HARDENING AND TextEditor_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TextEditor_ENABLE_SANITIZER_UNDEFINED
       OR TextEditor_ENABLE_SANITIZER_ADDRESS
       OR TextEditor_ENABLE_SANITIZER_THREAD
       OR TextEditor_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${TextEditor_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${TextEditor_ENABLE_SANITIZER_UNDEFINED}")
    TextEditor_enable_hardening(TextEditor_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(TextEditor_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(TextEditor_warnings INTERFACE)
  add_library(TextEditor_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  TextEditor_set_project_warnings(
    TextEditor_warnings
    ${TextEditor_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(TextEditor_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    TextEditor_configure_linker(TextEditor_options)
  endif()

  include(cmake/Sanitizers.cmake)
  TextEditor_enable_sanitizers(
    TextEditor_options
    ${TextEditor_ENABLE_SANITIZER_ADDRESS}
    ${TextEditor_ENABLE_SANITIZER_LEAK}
    ${TextEditor_ENABLE_SANITIZER_UNDEFINED}
    ${TextEditor_ENABLE_SANITIZER_THREAD}
    ${TextEditor_ENABLE_SANITIZER_MEMORY})

  set_target_properties(TextEditor_options PROPERTIES UNITY_BUILD ${TextEditor_ENABLE_UNITY_BUILD})

  if(TextEditor_ENABLE_PCH)
    target_precompile_headers(
      TextEditor_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(TextEditor_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    TextEditor_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(TextEditor_ENABLE_CLANG_TIDY)
    TextEditor_enable_clang_tidy(TextEditor_options ${TextEditor_WARNINGS_AS_ERRORS})
  endif()

  if(TextEditor_ENABLE_CPPCHECK)
    TextEditor_enable_cppcheck(${TextEditor_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(TextEditor_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    TextEditor_enable_coverage(TextEditor_options)
  endif()

  if(TextEditor_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(TextEditor_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(TextEditor_ENABLE_HARDENING AND NOT TextEditor_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TextEditor_ENABLE_SANITIZER_UNDEFINED
       OR TextEditor_ENABLE_SANITIZER_ADDRESS
       OR TextEditor_ENABLE_SANITIZER_THREAD
       OR TextEditor_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    TextEditor_enable_hardening(TextEditor_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
