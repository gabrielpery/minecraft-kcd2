# GPL-3.0-or-later: the plugin uses libKCD2's GPLv3 KCSE API.
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "MineCome's native KCD2 adapter requires Windows x64")
endif()

set(MINECOME_LIBKCD2_ROOT "${PROJECT_SOURCE_DIR}/external/libKCD2" CACHE PATH
    "Pinned libKCD2 source tree supplying the KCSE API")
if(NOT EXISTS "${MINECOME_LIBKCD2_ROOT}/include/KCSE/KCSEAPI.h")
    message(FATAL_ERROR "Fetch the pinned libKCD2 reference before building the KCSE adapter")
endif()

add_library(minecome_kcse SHARED src/kcse_plugin.cpp)
target_compile_features(minecome_kcse PRIVATE cxx_std_20)
target_include_directories(minecome_kcse PRIVATE "${MINECOME_LIBKCD2_ROOT}/include")
target_compile_definitions(minecome_kcse PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(minecome_kcse PRIVATE minecome_bridge)
set_target_properties(minecome_kcse PROPERTIES OUTPUT_NAME "MineCome")
if(MSVC)
    target_compile_options(minecome_kcse PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()

add_library(minecome_tools_pose src/tools_pose.cpp)
target_include_directories(minecome_tools_pose PUBLIC include)
target_link_libraries(minecome_tools_pose PUBLIC minecome_protocol)
target_compile_features(minecome_tools_pose PUBLIC cxx_std_20)
add_executable(minecome_tools_host src/tools_http_host.cpp)
add_library(minecome_stone_mirror src/stone_mirror.cpp)
target_include_directories(minecome_stone_mirror PUBLIC include)
target_link_libraries(minecome_stone_mirror PUBLIC minecome_protocol)
target_link_libraries(minecome_tools_host PRIVATE minecome_bridge minecome_tools_pose minecome_stone_mirror winhttp version)
target_compile_definitions(minecome_tools_host PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
    target_compile_options(minecome_tools_pose PRIVATE /W4 /permissive- /utf-8 /EHsc)
    target_compile_options(minecome_tools_host PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()

if(BUILD_TESTING)
    set(MINECOME_TEST_PYTHON "" CACHE FILEPATH "Existing Python interpreter for standalone Lua tests")
    set(MINECOME_LUA_LIBRARY "" CACHE FILEPATH "Explicit existing Lua 5.1/5.2 library; never installed by MineCome")
    if(EXISTS "${MINECOME_TEST_PYTHON}" AND EXISTS "${MINECOME_LUA_LIBRARY}")
        add_test(NAME lua_stone_sink_lifecycle COMMAND "${MINECOME_TEST_PYTHON}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_lua_sink_tests.py" --lua-library "${MINECOME_LUA_LIBRARY}")
    endif()
    add_executable(stone_mirror_tests tests/stone_mirror_tests.cpp)
    target_link_libraries(stone_mirror_tests PRIVATE minecome_stone_mirror)
    add_test(NAME stone_alignment_and_receipts COMMAND stone_mirror_tests)
    find_program(MINECOME_NODE_EXECUTABLE node)
    if(MINECOME_NODE_EXECUTABLE)
        add_test(NAME tools_stone_session_integration COMMAND "${MINECOME_NODE_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/tools_stone_integration.mjs"
            "$<TARGET_FILE:minecome_tools_host>" "${PROJECT_SOURCE_DIR}")
        set_tests_properties(tools_stone_session_integration PROPERTIES TIMEOUT 30)
        add_test(NAME tools_stone_input_integration COMMAND "${MINECOME_NODE_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/tools_stone_integration.mjs"
            "$<TARGET_FILE:minecome_tools_host>" "${PROJECT_SOURCE_DIR}" --interactive)
        set_tests_properties(tools_stone_input_integration PROPERTIES TIMEOUT 30)
    endif()
    add_executable(tools_pose_tests tests/tools_pose_tests.cpp)
    target_link_libraries(tools_pose_tests PRIVATE minecome_tools_pose)
    add_test(NAME tools_pose_and_camera_basis COMMAND tools_pose_tests)
    add_executable(kcse_adapter_smoke tests/kcse_adapter_smoke.cpp)
    target_include_directories(kcse_adapter_smoke PRIVATE "${MINECOME_LIBKCD2_ROOT}/include")
    target_compile_features(kcse_adapter_smoke PRIVATE cxx_std_20)
    target_compile_definitions(kcse_adapter_smoke PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(kcse_adapter_smoke PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME kcse_adapter_abi_and_lifecycle
        COMMAND kcse_adapter_smoke "$<TARGET_FILE:minecome_kcse>" "${CMAKE_BINARY_DIR}/test-kcse")
endif()

# Deliberately no kcd_re link or memory offsets: the exact Steam address library
# is absent. Loading this DLL through an unverified KCSE loader is unsupported.
