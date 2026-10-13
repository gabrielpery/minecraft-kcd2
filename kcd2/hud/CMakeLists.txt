# Original addon built against separately acquired ReShade v6.8.0 SDK headers.
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "MineCome's guarded HUD compositor requires Windows x64")
endif()
set(MINECOME_RESHADE_ROOT "${PROJECT_SOURCE_DIR}/external/reshade" CACHE PATH
    "Pinned ReShade v6.8.0 source (18deaa52de0c425a78b329e9cb3c497281cd00ec)")
if(NOT EXISTS "${MINECOME_RESHADE_ROOT}/include/reshade.hpp")
    message(FATAL_ERROR "Fetch the pinned ReShade SDK; no dependencies are installed by this build")
endif()

# The continuous experiment has distinct outputs and never replaces a previously
# verified static addon. Deployment remains an explicit controller operation.
add_library(minecome_hud_stream STATIC stream_contract.cpp stream_channel.cpp)
target_compile_features(minecome_hud_stream PUBLIC cxx_std_20)
target_include_directories(minecome_hud_stream PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(minecome_hud_stream PUBLIC WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_link_libraries(minecome_hud_stream PUBLIC minecome_hud_contract bcrypt)
add_executable(minecome_hud_stream_receiver stream_receiver.cpp)
target_link_libraries(minecome_hud_stream_receiver PRIVATE minecome_hud_stream)
add_library(minecome_hud_stream_compositor SHARED hud_stream_addon.cpp)
target_link_libraries(minecome_hud_stream_compositor PRIVATE minecome_hud_stream user32)
target_include_directories(minecome_hud_stream_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
set_target_properties(minecome_hud_stream_compositor PROPERTIES
    OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64")
set_target_properties(minecome_hud_stream_receiver minecome_hud_stream_compositor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/stream"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/stream"
    PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/stream")
if(MSVC)
    foreach(target minecome_hud_stream minecome_hud_stream_receiver minecome_hud_stream_compositor)
        set_target_properties(${target} PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endforeach()
endif()
add_custom_command(TARGET minecome_hud_stream_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeHud.fx"
        "$<TARGET_FILE_DIR:minecome_hud_stream_compositor>/MineComeHud.fx")
if(BUILD_TESTING)
    add_executable(minecome_hud_stream_tests stream_tests.cpp)
    target_link_libraries(minecome_hud_stream_tests PRIVATE minecome_hud_stream)
    if(MSVC)
        set_target_properties(minecome_hud_stream_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_stream_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_stream_contract_and_channel COMMAND minecome_hud_stream_tests)
endif()
add_library(minecome_hud_contract STATIC hud_contract.cpp)
target_include_directories(minecome_hud_contract PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(minecome_hud_contract PUBLIC cxx_std_20)
add_library(minecome_hud_compositor SHARED hud_addon.cpp)
target_compile_features(minecome_hud_compositor PRIVATE cxx_std_20)
target_include_directories(minecome_hud_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_compositor PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_link_libraries(minecome_hud_compositor PRIVATE minecome_hud_contract bcrypt user32)
set_target_properties(minecome_hud_compositor PROPERTIES
    OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64")
if(MSVC)
    foreach(target minecome_hud_contract minecome_hud_compositor)
        set_target_properties(${target} PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endforeach()
endif()
add_custom_command(TARGET minecome_hud_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeHud.fx"
        "$<TARGET_FILE_DIR:minecome_hud_compositor>/MineComeHud.fx")
if(BUILD_TESTING)
    add_executable(minecome_hud_contract_tests hud_contract_tests.cpp)
    target_link_libraries(minecome_hud_contract_tests PRIVATE minecome_hud_contract)
    if(MSVC)
        set_target_properties(minecome_hud_contract_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_contract_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_static_contract COMMAND minecome_hud_contract_tests)
endif()

# Reverse UI input has a distinct build/output profile. The frozen streaming
# renderer and its installed artifact are never rebuilt by this target.
add_library(minecome_hud_input STATIC input_contract.cpp input_channel.cpp)
target_link_libraries(minecome_hud_input PUBLIC minecome_hud_stream)
add_executable(minecome_hud_input_fixture input_fixture.cpp)
target_link_libraries(minecome_hud_input_fixture PRIVATE minecome_hud_input)
add_library(minecome_hud_input_compositor SHARED hud_input_addon.cpp)
target_link_libraries(minecome_hud_input_compositor PRIVATE minecome_hud_input user32)
target_include_directories(minecome_hud_input_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_input_compositor PRIVATE MINECOME_HUD_UI_INPUT=1)
set_target_properties(minecome_hud_input_compositor PROPERTIES OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64")
set_target_properties(minecome_hud_input_fixture minecome_hud_input_compositor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/input"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/input"
    PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/input")
if(MSVC)
    foreach(target minecome_hud_input minecome_hud_input_fixture minecome_hud_input_compositor)
        set_target_properties(${target} PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endforeach()
endif()

# Separate strict-mouse profile; the keyboard artifact and shader stay unchanged.
add_library(minecome_hud_mouse_compositor SHARED hud_input_addon.cpp)
target_link_libraries(minecome_hud_mouse_compositor PRIVATE minecome_hud_input user32)
target_include_directories(minecome_hud_mouse_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_mouse_compositor PRIVATE MINECOME_HUD_UI_INPUT=1 MINECOME_HUD_LIVE_MOUSE=1)
set_target_properties(minecome_hud_mouse_compositor PROPERTIES OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mouse" ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mouse")
if(MSVC)
    set_target_properties(minecome_hud_mouse_compositor PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(minecome_hud_mouse_compositor PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()
add_custom_command(TARGET minecome_hud_mouse_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeMouseHud.fx"
    "$<TARGET_FILE_DIR:minecome_hud_mouse_compositor>/MineComeHud.fx")

# Physical world-button experiment is opt-in and has its own arm filename and
# output. It retains strict API v1 capture (including camera axes) for its lease.
add_library(minecome_hud_world_compositor SHARED hud_input_addon.cpp)
target_link_libraries(minecome_hud_world_compositor PRIVATE minecome_hud_input user32)
target_include_directories(minecome_hud_world_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_world_compositor PRIVATE MINECOME_HUD_UI_INPUT=1 MINECOME_HUD_LIVE_MOUSE=1 MINECOME_HUD_WORLD_CLICKS=1)
set_target_properties(minecome_hud_world_compositor PROPERTIES OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/world" ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/world"
    PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/world")
if(MSVC)
    set_target_properties(minecome_hud_world_compositor PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(minecome_hud_world_compositor PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()
add_custom_command(TARGET minecome_hud_world_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeMouseHud.fx"
    "$<TARGET_FILE_DIR:minecome_hud_world_compositor>/MineComeHud.fx")

# API v2 is built and staged independently of the verified full-capture lab.
add_library(minecome_hud_selective_compositor SHARED hud_input_addon.cpp)
target_link_libraries(minecome_hud_selective_compositor PRIVATE minecome_hud_input user32)
target_include_directories(minecome_hud_selective_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_selective_compositor PRIVATE MINECOME_HUD_UI_INPUT=1 MINECOME_HUD_LIVE_MOUSE=1 MINECOME_HUD_WORLD_CLICKS=1 MINECOME_HUD_SELECTIVE_MOUSE=1)
set_target_properties(minecome_hud_selective_compositor PROPERTIES OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/selective" ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/selective"
    PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/selective")
if(MSVC)
    set_target_properties(minecome_hud_selective_compositor PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(minecome_hud_selective_compositor PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()
add_custom_command(TARGET minecome_hud_selective_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeMouseHud.fx"
    "$<TARGET_FILE_DIR:minecome_hud_selective_compositor>/MineComeHud.fx")

# Selective revision 2 adds motion-route filtering and separate diagnostics;
# it keeps the existing capture ABI and its previous frozen output untouched.
add_library(minecome_hud_motion_compositor SHARED hud_input_addon.cpp)
target_link_libraries(minecome_hud_motion_compositor PRIVATE minecome_hud_input user32)
target_include_directories(minecome_hud_motion_compositor PRIVATE "${MINECOME_RESHADE_ROOT}/include")
target_compile_definitions(minecome_hud_motion_compositor PRIVATE MINECOME_HUD_UI_INPUT=1 MINECOME_HUD_LIVE_MOUSE=1 MINECOME_HUD_WORLD_CLICKS=1 MINECOME_HUD_SELECTIVE_MOUSE=1 MINECOME_HUD_MOTION_FILTER=1)
set_target_properties(minecome_hud_motion_compositor PROPERTIES OUTPUT_NAME "MineComeHudCompositor" PREFIX "" SUFFIX ".addon64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/motion" ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/motion"
    PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/motion")
if(MSVC)
    set_target_properties(minecome_hud_motion_compositor PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(minecome_hud_motion_compositor PRIVATE /W4 /permissive- /utf-8 /EHsc)
endif()
add_custom_command(TARGET minecome_hud_motion_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeMouseHud.fx"
    "$<TARGET_FILE_DIR:minecome_hud_motion_compositor>/MineComeHud.fx")
if(BUILD_TESTING)
    add_executable(minecome_hud_selective_forwarding_tests selective_forwarding_tests.cpp)
    target_compile_features(minecome_hud_selective_forwarding_tests PRIVATE cxx_std_20)
    if(MSVC)
        set_target_properties(minecome_hud_selective_forwarding_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_selective_forwarding_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_selective_forwarding COMMAND minecome_hud_selective_forwarding_tests)
endif()
if(BUILD_TESTING)
    add_executable(minecome_hud_world_click_tests world_click_tests.cpp)
    target_compile_features(minecome_hud_world_click_tests PRIVATE cxx_std_20)
    if(MSVC)
        set_target_properties(minecome_hud_world_click_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_world_click_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_world_click_policy_and_queue COMMAND minecome_hud_world_click_tests)
endif()
if(BUILD_TESTING)
    add_executable(minecome_hud_mouse_forwarding_tests mouse_forwarding_tests.cpp)
    target_link_libraries(minecome_hud_mouse_forwarding_tests PRIVATE minecome_hud_input)
    if(MSVC)
        set_target_properties(minecome_hud_mouse_forwarding_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()
    add_test(NAME hud_mouse_forwarding COMMAND minecome_hud_mouse_forwarding_tests)
endif()
add_custom_command(TARGET minecome_hud_input_compositor POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/shaders/MineComeHud.fx"
        "$<TARGET_FILE_DIR:minecome_hud_input_compositor>/MineComeHud.fx")
if(BUILD_TESTING)
    add_executable(minecome_hud_stone_fixture_tests input_stone_fixture_tests.cpp)
    target_link_libraries(minecome_hud_stone_fixture_tests PRIVATE minecome_hud_input)
    if(MSVC)
        set_target_properties(minecome_hud_stone_fixture_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_stone_fixture_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_stone_fixture_receipts COMMAND minecome_hud_stone_fixture_tests)
    add_executable(minecome_hud_input_tests input_tests.cpp)
    target_link_libraries(minecome_hud_input_tests PRIVATE minecome_hud_input)
    if(MSVC)
        set_target_properties(minecome_hud_input_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_hud_input_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_input_contract_and_channel COMMAND minecome_hud_input_tests)
endif()

if(BUILD_TESTING)
    add_executable(minecome_mouse_capture_tests mouse_capture_tests.cpp)
    target_compile_features(minecome_mouse_capture_tests PRIVATE cxx_std_17)
    target_include_directories(minecome_mouse_capture_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(minecome_mouse_capture_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(minecome_mouse_capture_tests PRIVATE user32 dxguid dinput8)
    if(MSVC)
        set_target_properties(minecome_mouse_capture_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_mouse_capture_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_mouse_capture_policy_and_adapter COMMAND minecome_mouse_capture_tests)
endif()

if(BUILD_TESTING)
    add_executable(minecome_selective_capture_tests selective_capture_tests.cpp)
    target_compile_features(minecome_selective_capture_tests PRIVATE cxx_std_17)
    target_include_directories(minecome_selective_capture_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(minecome_selective_capture_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(minecome_selective_capture_tests PRIVATE user32 dxguid dinput8)
    if(MSVC)
        set_target_properties(minecome_selective_capture_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_selective_capture_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_selective_capture_policy_and_adapter COMMAND minecome_selective_capture_tests)
endif()

if(BUILD_TESTING)
    add_executable(minecome_motion_capture_tests motion_capture_tests.cpp)
    target_compile_features(minecome_motion_capture_tests PRIVATE cxx_std_17)
    target_include_directories(minecome_motion_capture_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(minecome_motion_capture_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(minecome_motion_capture_tests PRIVATE user32 dxguid dinput8)
    if(MSVC)
        set_target_properties(minecome_motion_capture_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_motion_capture_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_motion_capture_policy_and_adapter COMMAND minecome_motion_capture_tests)
    add_executable(minecome_motion_sdk_compile_tests motion_sdk_compile_tests.cpp)
    target_compile_features(minecome_motion_sdk_compile_tests PRIVATE cxx_std_17)
    target_include_directories(minecome_motion_sdk_compile_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(minecome_motion_sdk_compile_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(minecome_motion_sdk_compile_tests PRIVATE user32 dxguid dinput8)
    if(MSVC)
        set_target_properties(minecome_motion_sdk_compile_tests PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        target_compile_options(minecome_motion_sdk_compile_tests PRIVATE /W4 /permissive- /utf-8 /EHsc)
    endif()
    add_test(NAME hud_motion_sdk_nokeystates COMMAND minecome_motion_sdk_compile_tests)
endif()
