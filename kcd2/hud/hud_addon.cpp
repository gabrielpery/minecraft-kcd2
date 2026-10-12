// Original MineCome adapter. Inspected ReShade v6.8.0, commit
// 18deaa52de0c425a78b329e9cb3c497281cd00ec: include/reshade_api.hpp
// (semantic bindings/effect callbacks), include/reshade_api_device.hpp
// (owned resource lifetime), source/d3d12/d3d12_impl_device.cpp:392-420
// (initial-data upload is completed before return), source/addon_manager.cpp
// (AddonInit/AddonUninit are called outside DllMain before FreeLibrary).
// Microsoft primary references:
// https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-best-practices
// https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptcreatehash
// https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex
// This is STATIC snapshot compositing, not streaming or inventory interaction.
#include <Windows.h>
#include <bcrypt.h>
#include <reshade.hpp>
#include "hud_contract.hpp"
#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {
namespace api = reshade::api;
namespace hud = minecome::hud;
constexpr char exe_sha[] = "a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a";
constexpr char effect_name[] = "MineComeHud.fx";
constexpr std::array<const char *, 3> semantics{"MINECOME_HUD_1", "MINECOME_HUD_2", "MINECOME_HUD_3"};
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE v = INVALID_HANDLE_VALUE) : value(v) {}
    ~Handle() { if (value != nullptr && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(const Handle &) = delete; Handle &operator=(const Handle &) = delete;
    explicit operator bool() const { return value != nullptr && value != INVALID_HANDLE_VALUE; }
};
std::uint64_t utc_ms() {
    FILETIME ft{}; GetSystemTimeAsFileTime(&ft);
    const auto ticks = (static_cast<std::uint64_t>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    return ticks >= 116444736000000000ULL ? (ticks - 116444736000000000ULL) / 10000 : 0;
}
std::uint64_t steady_ms() { return GetTickCount64(); }
std::uint64_t process_start() {
    FILETIME creation{}, exit{}, kernel{}, user{};
    if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user)) return 0;
    return (static_cast<std::uint64_t>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
}
std::wstring module_path(HMODULE module) {
    std::wstring path(32768, L'\0');
    const DWORD n = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!n || n >= path.size()) return {};
    path.resize(n); return path;
}
std::wstring from_utf8(std::string_view path) {
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), nullptr, 0);
    if (n <= 0) return {};
    std::wstring result(static_cast<std::size_t>(n), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), result.data(), n) != n) return {};
    return result;
}
void receipt(std::string_view event, std::string_view result, std::string_view run = {}) {
    // All values are our fixed literals or validated hexadecimal identifiers.
    const std::string message = "[MineComeHud] {\"schema\":1,\"event\":\"" + std::string(event) +
        "\",\"result\":\"" + std::string(result) + "\",\"run\":\"" + std::string(run) +
        "\",\"static_snapshot\":true,\"visual_verified\":false}";
    reshade::log::message(reshade::log::level::info, message.c_str());
}
struct Hash {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    Hash() {
        if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0 &&
            BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0) hash = nullptr;
    }
    ~Hash() { if (hash) BCryptDestroyHash(hash); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
    bool add(std::span<const std::uint8_t> data) {
        return hash && BCryptHashData(hash, const_cast<PUCHAR>(data.data()), static_cast<ULONG>(data.size()), 0) >= 0;
    }
    std::string finish() {
        std::array<std::uint8_t, 32> value{};
        if (!hash || BCryptFinishHash(hash, value.data(), static_cast<ULONG>(value.size()), 0) < 0) return {};
        constexpr char digits[] = "0123456789abcdef"; std::string result; result.reserve(64);
        for (const auto b : value) { result += digits[b >> 4]; result += digits[b & 15]; }
        return result;
    }
};
struct Publication {
    hud::Arm arm;
    hud::Lease lease;
    std::array<std::vector<std::uint8_t>, 3> pixels;
};
class Service {
public:
    Handle stop{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    std::atomic<bool> compatible{false};
    std::atomic<std::shared_ptr<const Publication>> publication;
    std::thread worker;
    std::wstring config;
    std::uint32_t pid = GetCurrentProcessId();
    std::uint64_t start = process_start();
    explicit Service(HMODULE module) {
        const auto path = module_path(module); const auto slash = path.find_last_of(L"/\\");
        if (slash != path.npos) config = path.substr(0, slash + 1) + L"MineComeHud.ini";
    }
    bool stopping() const { return !stop || WaitForSingleObject(stop.value, 0) == WAIT_OBJECT_0; }
    // Disk IO exists only here on the worker. No render callback opens files or
    // waits for the worker. Local fixed drives + bounded overlapped reads avoid
    // network paths; cancelled OVERLAPPED buffers remain alive until completion.
    bool read(const std::wstring &path, std::uint64_t maximum, std::uint64_t exact,
              std::vector<std::uint8_t> *bytes, std::string *digest) {
        if (path.size() < 3 || path[1] != L':' || (path[2] != L'\\' && path[2] != L'/')) return false;
        wchar_t drive[]{path[0], L':', L'\\', L'\0'};
        if (GetDriveTypeW(drive) != DRIVE_FIXED || stopping()) return false;
        Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                FILE_FLAG_OVERLAPPED | FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
        if (!file) return false;
        BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER length{};
        if (!GetFileInformationByHandle(file.value, &info) || !GetFileSizeEx(file.value, &length) ||
            info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) ||
            length.QuadPart <= 0 || static_cast<std::uint64_t>(length.QuadPart) > maximum ||
            exact && static_cast<std::uint64_t>(length.QuadPart) != exact) return false;
        Handle completed(CreateEventW(nullptr, TRUE, FALSE, nullptr));
        if (!completed) return false;
        const auto size = static_cast<std::uint64_t>(length.QuadPart);
        if (bytes) { bytes->clear(); bytes->reserve(static_cast<std::size_t>(size)); }
        Hash hash;
        if (digest && !hash.hash) return false;
        std::array<std::uint8_t, 65536> chunk{};
        for (std::uint64_t offset = 0; offset < size;) {
            if (stopping()) return false;
            OVERLAPPED io{}; io.Offset = static_cast<DWORD>(offset);
            io.OffsetHigh = static_cast<DWORD>(offset >> 32); io.hEvent = completed.value;
            ResetEvent(completed.value);
            DWORD got = 0; const DWORD want = static_cast<DWORD>(std::min<std::uint64_t>(chunk.size(), size - offset));
            if (!ReadFile(file.value, chunk.data(), want, nullptr, &io)) {
                if (GetLastError() != ERROR_IO_PENDING) return false;
                HANDLE events[]{stop.value, completed.value};
                const auto wait = WaitForMultipleObjects(2, events, FALSE, 2000);
                if (wait != WAIT_OBJECT_0 + 1) {
                    CancelIoEx(file.value, &io);
                    // Win32 requires completion before freeing io/chunk/event.
                    GetOverlappedResult(file.value, &io, &got, TRUE);
                    return false;
                }
            }
            // Both immediate and pending asynchronous completion obtain their
            // actual byte count from OVERLAPPED, never lpNumberOfBytesRead.
            if (!GetOverlappedResult(file.value, &io, &got, FALSE)) return false;
            if (got != want) return false;
            if (digest && !hash.add(std::span(chunk.data(), got))) return false;
            if (bytes) bytes->insert(bytes->end(), chunk.begin(), chunk.begin() + got);
            offset += got;
        }
        if (digest) { *digest = hash.finish(); if (digest->empty()) return false; }
        return !stopping();
    }
    void run() noexcept {
        try {
            std::string digest;
            if (!start || config.empty() || !read(module_path(nullptr), 512u * 1024u * 1024u, 0, nullptr, &digest) || digest != exe_sha) {
                receipt("compatibility", "exe_rejected"); return;
            }
            compatible.store(true, std::memory_order_release);
            receipt("compatibility", "exact_tools_exe");
            std::string last_error;
            while (!stopping()) {
                std::vector<std::uint8_t> config_bytes;
                if (read(config, hud::max_config_bytes, 0, &config_bytes, nullptr)) {
                    hud::Arm arm; std::string error;
                    const std::string_view text(reinterpret_cast<const char *>(config_bytes.data()), config_bytes.size());
                    if (hud::parse_arm(text, pid, start, utc_ms(), arm, error)) {
                        auto next = std::make_shared<Publication>(); next->arm = std::move(arm);
                        bool loaded = true;
                        for (std::uint32_t i = 0; i < next->arm.frame_count; ++i) {
                            std::string actual;
                            if (!read(from_utf8(next->arm.frames[i].path), hud::max_frame_bytes,
                                      hud::byte_count(next->arm.width, next->arm.height), &next->pixels[i], &actual) ||
                                actual != next->arm.frames[i].sha256 ||
                                !hud::premultiply_rgba(next->pixels[i], next->arm.width, next->arm.height)) {
                                loaded = false; error = "frame_bytes_or_hash"; break;
                            }
                        }
                        if (loaded && next->lease.accept(next->arm, utc_ms(), steady_ms())) {
                            const auto run_token = next->arm.run;
                            publication.store(std::move(next), std::memory_order_release);
                            receipt("arm", "accepted", run_token);
                            // Never read a replacement arm. Runtime/FX reload does
                            // not restart this service or extend its fixed lease.
                            return;
                        }
                        if (error.empty()) error = "arm_expired_during_load";
                    }
                    if (error != last_error) { receipt("arm", error); last_error = error; }
                }
                WaitForSingleObject(stop.value, 100);
            }
        } catch (...) { receipt("worker", "failed"); }
    }
    void shutdown() {
        if (stop) SetEvent(stop.value);
        if (worker.joinable()) worker.join(); // AddonUninit only, never rendering/DllMain.
    }
};
Service *service = nullptr; // Explicit teardown in AddonUninit, not CRT/DllMain.
struct RuntimeState {
    HWND window = nullptr;
    std::array<api::resource, 3> textures{};
    std::array<api::resource_view, 3> views{};
    api::effect_uniform_variable active{}, frame{}, rect{};
    api::effect_technique technique{};
    bool bound = false, failed = false, expired_logged = false, shader_missing_logged = false;
    std::array<std::uint64_t, 3> submitted{};
    int last_frame = -1;
};
std::mutex runtimes_mutex;
std::unordered_map<api::effect_runtime *, RuntimeState> runtimes;
bool sdr(api::format format) {
    return format == api::format::r8g8b8a8_unorm || format == api::format::r8g8b8a8_unorm_srgb ||
           format == api::format::b8g8r8a8_unorm || format == api::format::b8g8r8a8_unorm_srgb;
}
bool owned_window(HWND window) {
    DWORD pid = 0;
    return window && IsWindow(window) && GetWindowThreadProcessId(window, &pid) && pid == GetCurrentProcessId();
}
bool visible_window(api::effect_runtime *runtime, const RuntimeState &state) {
    return reinterpret_cast<HWND>(runtime->get_hwnd()) == state.window && owned_window(state.window) &&
        !IsIconic(state.window) && IsWindowVisible(state.window) && GetForegroundWindow() == state.window;
}
void hide(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active != 0) runtime->set_uniform_value_bool(state.active, false);
}
bool handles(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active == 0) {
        state.active = runtime->find_uniform_variable(effect_name, "McHudActive");
        state.frame = runtime->find_uniform_variable(effect_name, "McHudFrame");
        state.rect = runtime->find_uniform_variable(effect_name, "McHudRect");
        state.technique = runtime->find_technique(effect_name, "MineComeHud");
    }
    if (state.active == 0 || state.frame == 0 || state.rect == 0 || state.technique == 0) {
        state.active = {}; state.frame = {}; state.rect = {}; state.technique = {};
        if (!state.shader_missing_logged) { receipt("effect", "not_ready"); state.shader_missing_logged = true; }
        return false;
    }
    return true;
}
void release(api::effect_runtime *runtime, RuntimeState &state,
             hud::TeardownMode mode = hud::TeardownMode::live_effects) {
    bool resources = false;
    for (const auto texture : state.textures) if (texture != 0) resources = true;
    const auto plan = hud::teardown_plan(mode, state.active != 0, state.bound, resources);
    if (plan.invalidate_effect_handles) {
        // Pinned runtime.cpp:637 destroys effects; :641-643 destroys the
        // fallback SRV; only :687 invokes destroy_effect_runtime. Cached FX
        // handles already dangle here. Never pass one to any uniform API.
        state.active = {}; state.frame = {}; state.rect = {}; state.technique = {};
    }
    if (plan.hide_effect) hide(runtime, state);
    if (plan.erase_semantic_cache) {
        // ReShade retains its external semantic cache across an FX reload.
        // Even when new handles are missing, retire every cached owned view
        // before destroying it; bound only tracks the current FX generation.
        // At runtime reset, runtime_api.cpp:670-744 only erases this cache:
        // _effects is empty, so no zero fallback SRV is sent to the GPU.
        for (const auto semantic : semantics) runtime->update_texture_bindings(semantic, {}, {});
        state.bound = false;
    }
    if (plan.destroy_owned_resources) {
        runtime->get_command_queue()->wait_idle();
        auto device = runtime->get_device();
        for (auto &view : state.views) { if (view != 0) device->destroy_resource_view(view); view = {}; }
        for (auto &texture : state.textures) { if (texture != 0) device->destroy_resource(texture); texture = {}; }
    }
}
bool allocate(api::effect_runtime *runtime, RuntimeState &state, const Publication &pub) {
    if (state.failed) return false;
    if (state.textures[0] != 0) return true;
    if (!runtime->get_command_queue()->get_immediate_command_list()) { state.failed = true; return false; }
    auto device = runtime->get_device();
    const api::resource_desc desc(pub.arm.width, pub.arm.height, 1, 1, api::format::r8g8b8a8_unorm, 1,
        api::memory_heap::default_, api::resource_usage::shader_resource | api::resource_usage::copy_dest);
    for (std::uint32_t i = 0; i < pub.arm.frame_count; ++i) {
        const api::subresource_data data{const_cast<std::uint8_t *>(pub.pixels[i].data()),
            pub.arm.width * 4, pub.arm.width * pub.arm.height * 4};
        if (!device->create_resource(desc, &data, api::resource_usage::shader_resource, &state.textures[i]) ||
            !device->create_resource_view(state.textures[i], api::resource_usage::shader_resource,
                                        api::resource_view_desc(api::format::r8g8b8a8_unorm), &state.views[i])) {
            release(runtime, state); state.failed = true; receipt("resources", "failed", pub.arm.run); return false;
        }
    }
    receipt("resources", "created", pub.arm.run); return true;
}
void on_init(api::effect_runtime *runtime) {
    if (runtime->get_device()->get_api() != api::device_api::d3d12) return;
    std::lock_guard lock(runtimes_mutex);
    RuntimeState state; state.window = reinterpret_cast<HWND>(runtime->get_hwnd());
    if (owned_window(state.window)) runtimes.try_emplace(runtime, std::move(state));
}
void on_destroy(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it = runtimes.find(runtime); if (it == runtimes.end()) return;
    release(runtime, it->second, hud::TeardownMode::after_runtime_reset);
    std::ostringstream message;
    message << "[MineComeHud] {\"schema\":1,\"event\":\"cleanup\",\"result\":\"owned_resources_released\",\"submitted\":["
        << it->second.submitted[0] << ',' << it->second.submitted[1] << ',' << it->second.submitted[2]
        << "],\"static_snapshot\":true,\"visual_verified\":false}";
    reshade::log::message(reshade::log::level::info, message.str().c_str());
    runtimes.erase(it);
}
void on_reload(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it = runtimes.find(runtime); if (it == runtimes.end()) return;
    auto &state = it->second;
    // SDK explicitly invalidates these effect handles. The GPU assets and lease
    // remain ours; semantic descriptors are rebound once to the new effect.
    state.active = {}; state.frame = {}; state.rect = {}; state.technique = {};
    state.bound = false; state.shader_missing_logged = false;
}
void on_begin(api::effect_runtime *runtime, api::command_list *, api::resource_view rtv, api::resource_view) {
    std::lock_guard lock(runtimes_mutex);
    const auto it = runtimes.find(runtime);
    if (it == runtimes.end() || !service || !service->compatible.load(std::memory_order_acquire)) return;
    auto &state = it->second;
    const auto pub = service->publication.load(std::memory_order_acquire);
    // A disarmed addon has no reason to query/copy shader handles or mutate
    // an effect. The shipped shader is inactive by default, and only a
    // verified immutable publication permits our first effect API write.
    if (!pub) return;
    const auto now = steady_ms();
    // Owned resource expiry is independent of successful FX compilation.
    // A missing/broken shader after reload cannot retain textures indefinitely.
    if (!pub->lease.live(utc_ms(), now)) {
        if (!state.expired_logged) { receipt("lease", "expired", pub->arm.run); state.expired_logged = true; }
        release(runtime, state); state.failed = true; return;
    }
    if (!handles(runtime, state)) return;
    hide(runtime, state);
    if (!visible_window(runtime, state) || rtv == 0 ||
        runtime->get_device()->get_api() != api::device_api::d3d12 ||
        !sdr(runtime->get_device()->get_resource_view_desc(rtv).format)) return;
    const auto target = runtime->get_device()->get_resource_from_view(rtv);
    if (target == 0) return;
    const auto desc = runtime->get_device()->get_resource_desc(target);
    if (desc.type != api::resource_type::texture_2d || !sdr(desc.texture.format)) return;
    const auto rectangle = hud::fit_rect(pub->arm.width, pub->arm.height, desc.texture.width, desc.texture.height);
    if (rectangle.width <= 0 || rectangle.height <= 0 || !allocate(runtime, state, *pub)) return;
    if (!state.bound) {
        for (std::uint32_t i = 0; i < 3; ++i) {
            const auto view = state.views[i < pub->arm.frame_count ? i : 0];
            runtime->update_texture_bindings(semantics[i], view, view);
        }
        state.bound = true;
    }
    // SDK initial-data uploads and semantic replacement may wait for the GPU.
    // They must not turn an expired or newly unfocused preview back on.
    const auto display_now = steady_ms();
    if (!pub->lease.live(utc_ms(), display_now)) {
        if (!state.expired_logged) { receipt("lease", "expired", pub->arm.run); state.expired_logged = true; }
        release(runtime, state); state.failed = true; return;
    }
    if (!visible_window(runtime, state)) return;
    const auto index = pub->lease.frame_index(display_now);
    runtime->set_uniform_value_float(state.rect, rectangle.x, rectangle.y, rectangle.width, rectangle.height);
    runtime->set_uniform_value_int(state.frame, static_cast<std::int32_t>(index));
    runtime->set_technique_state(state.technique, true);
    runtime->set_uniform_value_bool(state.active, true);
    ++state.submitted[index];
    if (state.last_frame != static_cast<int>(index)) {
        const std::string result = "snapshot_" + std::to_string(index + 1) + "_submitted";
        receipt("frame", result, pub->arm.run); state.last_frame = static_cast<int>(index);
    }
}
} // namespace

extern "C" __declspec(dllexport) const char *NAME = "MineCome static Minecraft HUD proof";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Exact KCD2 tools/D3D12 guarded static RGBA snapshots; no input or streaming.";
extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon_module, HMODULE reshade_module) {
    if (!reshade::register_addon(addon_module, reshade_module)) return false;
    try {
        service = new Service(addon_module);
        if (!service->stop || service->config.empty()) throw std::runtime_error("service_init");
        service->worker = std::thread([] { service->run(); });
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy);
        reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reload);
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin);
        receipt("addon", "disarmed"); return true;
    } catch (...) {
        if (service) { service->shutdown(); delete service; service = nullptr; }
        reshade::unregister_addon(addon_module, reshade_module); return false;
    }
}
extern "C" __declspec(dllexport) void AddonUninit(HMODULE addon_module, HMODULE reshade_module) {
    reshade::unregister_event<reshade::addon_event::init_effect_runtime>(on_init);
    reshade::unregister_event<reshade::addon_event::destroy_effect_runtime>(on_destroy);
    reshade::unregister_event<reshade::addon_event::reshade_reloaded_effects>(on_reload);
    reshade::unregister_event<reshade::addon_event::reshade_begin_effects>(on_begin);
    // Explicit unload entry point runs before FreeLibrary, outside DllMain.
    // Every worker read is overlapped/cancellable; never detach running code.
    if (service) service->shutdown();
    {
        std::lock_guard lock(runtimes_mutex);
        for (auto &[runtime, state] : runtimes) release(runtime, state);
        runtimes.clear();
        delete service; service = nullptr;
    }
    receipt("addon", "worker_joined_resources_released");
    reshade::unregister_addon(addon_module, reshade_module);
}
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}
