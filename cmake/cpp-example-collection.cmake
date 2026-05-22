# Copyright 2026 LiveKit, Inc.
#
# LiveKit examples integration helpers.

include_guard(GLOBAL)

function(livekit_configure_cpp_example_collection)
  include(GNUInstallDirs)

  # Absolute paths so out-of-tree builds and symlinks behave consistently.
  get_filename_component(LIVEKIT_CPP_EXAMPLES_SOURCE_DIR
    "${LIVEKIT_ROOT_DIR}/cpp-example-collection" ABSOLUTE)

  get_filename_component(_lk_examples_install_default
    "${LIVEKIT_ROOT_DIR}/local-install" ABSOLUTE)
  set(LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX "${_lk_examples_install_default}"
    CACHE PATH "Install prefix used by cpp-example-collection")

  get_filename_component(_lk_examples_binary_default
    "${CMAKE_BINARY_DIR}/cpp-example-collection-build" ABSOLUTE)
  set(LIVEKIT_CPP_EXAMPLES_BINARY_DIR "${_lk_examples_binary_default}"
    CACHE PATH "Build directory for cpp-example-collection")

  get_filename_component(LIVEKIT_CPP_EXAMPLES_LIVEKIT_DIR
    "${LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/cmake/LiveKit"
    ABSOLUTE)

  if(NOT EXISTS "${LIVEKIT_CPP_EXAMPLES_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
      "cpp-example-collection submodule is missing. Run: "
      "git submodule sync --recursive && "
      "git submodule update --init --recursive --checkout")
  endif()

  add_custom_target(install_livekit_sdk_for_examples
    COMMAND ${CMAKE_COMMAND} -E make_directory "${LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX}"
    COMMAND ${CMAKE_COMMAND} --install "${CMAKE_BINARY_DIR}"
            --prefix "${LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX}"
            --config "$<CONFIG>"
    DEPENDS livekit
    COMMENT "Installing LiveKit SDK for cpp-example-collection"
    VERBATIM
  )

  set(_lk_examples_configure_args
    "-DCMAKE_PREFIX_PATH=${LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX}"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    "-DLIVEKIT_LOCAL_SDK_DIR=${LIVEKIT_CPP_EXAMPLES_INSTALL_PREFIX}"
    "-DLiveKit_DIR=${LIVEKIT_CPP_EXAMPLES_LIVEKIT_DIR}"
  )

  if(APPLE AND CMAKE_OSX_ARCHITECTURES)
    list(APPEND _lk_examples_configure_args
      "-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}"
    )
  endif()

  # RV1126B port: the example collection is configured as a *separate* CMake
  # project, so it does not inherit the parent's cross-compilation toolchain.
  # Without this it would silently build for the host. Propagate the toolchain
  # file (resolved to an absolute path) so board_loopback and the other
  # examples come out as aarch64 ELF matching the cross-built SDK. The sysroot
  # / compiler env vars (ATK_TOOLCHAIN_ROOT, ATK_SYSROOT) are inherited by the
  # child process from scripts/env-rv1126b.sh.
  if(CMAKE_CROSSCOMPILING AND CMAKE_TOOLCHAIN_FILE)
    get_filename_component(_lk_examples_toolchain "${CMAKE_TOOLCHAIN_FILE}"
      ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
    list(APPEND _lk_examples_configure_args
      "-DCMAKE_TOOLCHAIN_FILE=${_lk_examples_toolchain}"
    )
  endif()

  add_custom_target(cpp_example_collection ALL
    COMMAND ${CMAKE_COMMAND} -S "${LIVEKIT_CPP_EXAMPLES_SOURCE_DIR}"
            -B "${LIVEKIT_CPP_EXAMPLES_BINARY_DIR}"
            ${_lk_examples_configure_args}
    COMMAND ${CMAKE_COMMAND} --build "${LIVEKIT_CPP_EXAMPLES_BINARY_DIR}"
            --config "$<CONFIG>"
    DEPENDS install_livekit_sdk_for_examples
    COMMENT "Configuring and building cpp-example-collection"
    VERBATIM
  )
endfunction()
