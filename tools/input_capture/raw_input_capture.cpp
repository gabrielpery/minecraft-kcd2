#include "input_state.hpp"

#include <Windows.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <filesystem>
#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

// Primary API contracts inspected 2026-10-12:
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getrawinputdata
// https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-input
// https://learn.microsoft.com/en-us/windows/win32/inputdev/using-raw-input
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawkeyboard
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawmouse
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate
// https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getregisteredrawinputdevices
// https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-input-device-change
// https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew
// https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nc-winuser-wineventproc
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unhookwinevent
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessagetime

namespace {
namespace ic = minecome::input_capture;
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
constexpr wchar_t window_class[] = L"MineComeObserveRawInputV1";
constexpr DWORD registration_flags = RIDEV_INPUTSINK | RIDEV_DEVNOTIFY;
constexpr std::array<int, ic::control_count> control_vkeys{'W', 'S', 'A', 'D', VK_SPACE, VK_LSHIFT};
std::atomic_bool shutdown_requested{};

struct Handle {
    HANDLE value{INVALID_HANDLE_VALUE};
    explicit Handle(HANDLE h = INVALID_HANDLE_VALUE) : value(h) {}
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    bool valid() const { return value && value != INVALID_HANDLE_VALUE; }
};

std::string ascii(std::wstring_view text) {
    std::string result;
    for (wchar_t c : text) {
        if (c < 0 || c > 127) throw std::invalid_argument("argument requires ASCII");
        result.push_back(static_cast<char>(c));
    }
    return result;
}

struct Options {
    ic::RecordIdentity identity;
    std::uint64_t start{};
    unsigned seconds{};
    fs::path output;
};

Options options(int argc, wchar_t** argv) {
    if (argc != 11) throw std::invalid_argument("usage: --target-pid N --target-start FILETIME --run lowerhex32 --output absolute-new-file --seconds 15..120");
    Options result;
    unsigned seen{};
    for (int i = 1; i < argc; i += 2) {
        const std::wstring_view key(argv[i]);
        const std::wstring_view value(argv[i + 1]);
        unsigned bit{};
        if (key == L"--target-pid") {
            bit = 1;
            std::uint64_t parsed{};
            if (!ic::canonical_positive_decimal(ascii(value), parsed) || parsed > std::numeric_limits<DWORD>::max())
                throw std::invalid_argument("invalid target pid");
            result.identity.target_pid = static_cast<DWORD>(parsed);
        } else if (key == L"--target-start") {
            bit = 2;
            result.identity.target_start_filetime = ascii(value);
            if (!ic::canonical_positive_decimal(result.identity.target_start_filetime, result.start))
                throw std::invalid_argument("invalid target creation FILETIME");
        } else if (key == L"--run") {
            bit = 4;
            result.identity.run = ascii(value);
            if (!ic::valid_run(result.identity.run)) throw std::invalid_argument("invalid run");
        } else if (key == L"--output") {
            bit = 8;
            result.output = fs::path(value);
            if (!result.output.is_absolute() || !result.output.has_filename())
                throw std::invalid_argument("output must be an absolute new file");
        } else if (key == L"--seconds") {
            bit = 16;
            std::uint64_t parsed{};
            if (!ic::canonical_positive_decimal(ascii(value), parsed) || parsed < 15 || parsed > 120)
                throw std::invalid_argument("seconds must be 15..120");
            result.seconds = static_cast<unsigned>(parsed);
        } else throw std::invalid_argument("unknown argument");
        if (seen & bit) throw std::invalid_argument("duplicate argument");
        seen |= bit;
    }
    if (seen != 31) throw std::invalid_argument("missing argument");
    return result;
}

std::uint64_t filetime_value(FILETIME value) {
    return (static_cast<std::uint64_t>(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}

bool alive(HANDLE process) { return WaitForSingleObject(process, 0) == WAIT_TIMEOUT; }

std::wstring final_path(HANDLE handle) {
    const DWORD size = GetFinalPathNameByHandleW(handle, nullptr, 0, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (!size || size > 32768) throw std::runtime_error("cannot resolve output path");
    std::wstring result(size, L'\0');
    const DWORD written = GetFinalPathNameByHandleW(handle, result.data(), size, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (!written || written >= size) throw std::runtime_error("cannot resolve output path");
    result.resize(written);
    while (result.size() > 1 && result.back() == L'\\') result.pop_back();
    return result;
}

bool same_path(std::wstring_view a, std::wstring_view b) {
    return a.size() == b.size() && CompareStringOrdinal(a.data(), static_cast<int>(a.size()),
        b.data(), static_cast<int>(b.size()), TRUE) == CSTR_EQUAL;
}

bool inside(std::wstring_view child, std::wstring_view parent) {
    return child.size() > parent.size() && child[parent.size()] == L'\\' &&
        same_path(child.substr(0, parent.size()), parent);
}

fs::path project_root() {
    std::wstring exe(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
    if (!length || length >= exe.size()) throw std::runtime_error("cannot locate capture executable");
    exe.resize(length);
    const std::array<fs::path, 2> starts{fs::path(exe).parent_path(), fs::current_path()};
    for (auto path : starts) {
        for (unsigned i = 0; i < 20 && !path.empty(); ++i) {
            if (fs::is_regular_file(path / L"AGENTS.md") && fs::is_regular_file(path / L"CMakeLists.txt") &&
                fs::is_directory(path / L"minecraft")) return path;
            const auto parent = path.parent_path();
            if (parent == path) break;
            path = parent;
        }
    }
    throw std::runtime_error("cannot locate MineCome project root");
}

// Pins resolved existing directories without FILE_SHARE_DELETE. CREATE_NEW never
// truncates an existing file; no directory creation is performed by this helper.
class EvidenceWriter {
public:
    explicit EvidenceWriter(const fs::path& requested)
        : evidence_(CreateFileW((project_root() / L"runtime" / L"evidence").c_str(),
            FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
            OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr)),
          parent_(CreateFileW(requested.parent_path().c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr)) {
        if (!evidence_.valid() || !parent_.valid()) throw std::runtime_error("evidence parent must already exist");
        const auto evidence = final_path(evidence_.value);
        const auto parent = final_path(parent_.value);
        if (!same_path(parent, evidence) && !inside(parent, evidence))
            throw std::invalid_argument("output parent escapes runtime/evidence");
        const auto name = requested.filename().wstring();
        if (name.empty() || name == L"." || name == L".." || name.back() == L'.' || name.back() == L' ' ||
            name.find_first_of(L":\\/\"<>|?*") != std::wstring::npos)
            throw std::invalid_argument("invalid output filename");
        const fs::path resolved = fs::path(parent) / name;
        file_.value = CreateFileW(resolved.c_str(), GENERIC_WRITE | FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (!file_.valid()) throw std::runtime_error("output CREATE_NEW failed");
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(file_.value, &info) ||
            (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) ||
            !inside(final_path(file_.value), evidence)) throw std::runtime_error("output path verification failed");
    }
    bool write(const std::string& record, bool terminal = false) {
        constexpr std::size_t limit = 1024 * 1024;
        constexpr std::size_t terminal_reserve = 1024;
        // Reserve both bytes and a record for the terminal marker.
        if (records_ >= (terminal ? 2499U : 2498U) ||
            record.size() > 1024 || bytes_ + record.size() > limit - (terminal ? 0 : terminal_reserve)) return false;
        DWORD written{};
        if (!WriteFile(file_.value, record.data(), static_cast<DWORD>(record.size()), &written, nullptr) ||
            written != record.size() || !FlushFileBuffers(file_.value)) return false;
        bytes_ += record.size();
        ++records_;
        return true;
    }
private:
    Handle evidence_;
    Handle parent_;
    Handle file_;
    std::size_t records_{};
    std::size_t bytes_{};
};

ic::ControlBits current_controls() {
    ic::ControlBits result{};
    // Never use the unreliable LOW bit. Zero is ambiguous under desktop/UIPI
    // restrictions; this diagnostic does not establish engine gameplay state.
    for (unsigned i = 0; i < ic::control_count; ++i) result[i] = (GetAsyncKeyState(control_vkeys[i]) & 0x8000) != 0;
    return result;
}

struct Capture {
    DWORD target_pid{};
    HANDLE process{};
    ic::InputState state;
    DWORD epoch{GetTickCount()};
    DWORD dispatch_time{};
    HANDLE keyboard_device{};
    bool failed{};

    bool target_focused() const {
        if (!alive(process)) return false;
        const HWND foreground = GetForegroundWindow();
        DWORD pid{};
        return foreground && GetWindowThreadProcessId(foreground, &pid) && pid == target_pid;
    }
    bool update_focus() {
        const bool focused = target_focused();
        if (focused == state.focused()) return focused;
        if (focused) {
            const auto controls = current_controls();
            const bool f8 = (GetAsyncKeyState(VK_F8) & 0x8000) != 0;
            // Query only while the target is foreground, then verify again.
            if (!target_focused()) { state.focus(false); epoch = GetTickCount(); return false; }
            state.focus(true, controls, f8);
        } else state.focus(false);
        epoch = GetTickCount();
        keyboard_device = nullptr;
        return state.focused();
    }
    void disarm() { reset_baseline(); }
    void reset_baseline() {
        state.focus(false);
        keyboard_device = nullptr;
        update_focus();
        epoch = GetTickCount();
    }
    void input(LPARAM lparam) {
        // Background packets are never decoded or recorded. DefWindowProc is
        // still performed by WindowProc for cleanup, including filtered input.
        if (!update_focus()) return;
        const DWORD now = GetTickCount();
        const auto disposition = ic::classify_packet(dispatch_time, now, epoch);
        if (disposition == ic::PacketDisposition::stale) { disarm(); return; }
        if (disposition == ic::PacketDisposition::previous_epoch) {
            // Coarse-tick equality is common at high mouse rates. Drop it without
            // renewing the epoch or disarming this phase. Seed only suppression
            // so a discarded key MAKE cannot become a fresh typematic edge.
            state.suppress_currently_down(current_controls());
            state.suppress_f8_until_release((GetAsyncKeyState(VK_F8) & 0x8000) != 0);
            return;
        }
        UINT required{};
        const auto raw_handle = reinterpret_cast<HRAWINPUT>(lparam);
        if (GetRawInputData(raw_handle, RID_INPUT, nullptr, &required, sizeof(RAWINPUTHEADER)) != 0 ||
            required < sizeof(RAWINPUTHEADER) || required > sizeof(RAWINPUT)) { disarm(); return; }
        RAWINPUT raw{}; // Naturally aligned; no allocation from untrusted sizes.
        UINT capacity = required;
        const UINT read = GetRawInputData(raw_handle, RID_INPUT, &raw, &capacity, sizeof(RAWINPUTHEADER));
        if (read == static_cast<UINT>(-1) || read != required || capacity != required ||
            raw.header.dwSize != read || read > sizeof(raw)) { disarm(); return; }
        // A foreground switch between the filter and data read discards data.
        if (!update_focus()) return;
        if (raw.header.dwType == RIM_TYPEKEYBOARD) {
            if (read < offsetof(RAWINPUT, data) + sizeof(RAWKEYBOARD)) { disarm(); return; }
            if (!raw.header.hDevice) { disarm(); return; }
            if (keyboard_device && keyboard_device != raw.header.hDevice) {
                // Conservative multi-keyboard ambiguity: require a new baseline
                // and arm. Device identities never enter evidence or stdout.
                reset_baseline();
                keyboard_device = raw.header.hDevice;
                return;
            }
            keyboard_device = raw.header.hDevice;
            const auto& key = raw.data.keyboard;
            if (key.MakeCode == KEYBOARD_OVERRUN_MAKE_CODE || key.VKey >= 255 || key.Reserved ||
                (key.Flags & ~(RI_KEY_BREAK | RI_KEY_E0 | RI_KEY_E1))) { disarm(); return; }
            const bool down = !(key.Flags & RI_KEY_BREAK);
            if ((down && key.Message != WM_KEYDOWN && key.Message != WM_SYSKEYDOWN) ||
                (!down && key.Message != WM_KEYUP && key.Message != WM_SYSKEYUP)) { disarm(); return; }
            UINT vk = key.VKey;
            if (vk == VK_SHIFT) {
                UINT scan = key.MakeCode;
                if (key.Flags & RI_KEY_E0) scan |= 0xe000;
                if (key.Flags & RI_KEY_E1) scan |= 0xe100;
                vk = MapVirtualKeyW(scan, MAPVK_VSC_TO_VK_EX);
            }
            if (vk == VK_F8) {
                const bool was_armed = state.armed();
                if (down && !was_armed) state.suppress_currently_down(current_controls());
                state.f8(down);
                if (!was_armed && state.armed()) epoch = GetTickCount();
                return;
            }
            for (unsigned i = 0; i < ic::control_count; ++i) {
                if (vk == static_cast<UINT>(control_vkeys[i])) { state.control(static_cast<ic::Control>(i), down); return; }
            }
            // Ctrl/Alt/other Shift keys are not captured. All other unsupported
            // presses (including Esc/backtick) conservatively disarm.
            const bool modifier = vk == VK_SHIFT || vk == VK_LSHIFT || vk == VK_RSHIFT ||
                vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL ||
                vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU;
            if (down && !modifier) disarm();
        } else if (raw.header.dwType == RIM_TYPEMOUSE) {
            if (read < offsetof(RAWINPUT, data) + sizeof(RAWMOUSE)) { disarm(); return; }
            const auto& mouse = raw.data.mouse;
            if (mouse.usButtonFlags || (mouse.usFlags & (MOUSE_MOVE_ABSOLUTE | MOUSE_VIRTUAL_DESKTOP | MOUSE_ATTRIBUTES_CHANGED)) ||
                (mouse.usFlags & ~MOUSE_MOVE_NOCOALESCE)) { disarm(); return; }
            // MOUSE_MOVE_RELATIVE is zero; it is not a flag to test with &.
            state.relative_mouse(mouse.lLastX, mouse.lLastY);
        } else disarm();
    }
};

thread_local Capture* foreground_capture{};

void CALLBACK foreground_event(HWINEVENTHOOK, DWORD event, HWND, LONG, LONG, DWORD, DWORD) {
    // OUTOFCONTEXT delivers on this registration thread. Do not query or log
    // the event's window, owner, title or accessibility objects. Every transition
    // is conservative, including destroyed/unknown HWNDs and another target window.
    if (event != EVENT_SYSTEM_FOREGROUND || !foreground_capture) return;
    foreground_capture->state.focus(false);
    foreground_capture->keyboard_device = nullptr;
    foreground_capture->epoch = GetTickCount();
}

class ForegroundObserver {
public:
    explicit ForegroundObserver(Capture& capture) {
        foreground_capture = &capture;
        hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
            nullptr, foreground_event, 0, 0, WINEVENT_OUTOFCONTEXT);
        if (!hook_) { foreground_capture = nullptr; throw std::runtime_error("foreground observer registration failed"); }
    }
    ~ForegroundObserver() { cleanup(); }
    bool cleanup() noexcept {
        if (!hook_) return cleanup_ok_;
        cleanup_ok_ = UnhookWinEvent(hook_) != FALSE;
        hook_ = nullptr;
        foreground_capture = nullptr;
        std::cout << "FOCUS_OBSERVER_CLEANUP unhooked=" << (cleanup_ok_ ? "true" : "false") << '\n' << std::flush;
        return cleanup_ok_;
    }
private:
    HWINEVENTHOOK hook_{};
    bool cleanup_ok_{true};
};

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* capture = reinterpret_cast<Capture*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_INPUT) {
        try { if (capture) capture->input(lparam); }
        catch (...) { if (capture) { capture->failed = true; capture->disarm(); } }
        // Read first. Calling this for both codes also covers every rejected
        // RIM_INPUT path where the system explicitly requires cleanup.
        DefWindowProcW(hwnd, message, wparam, lparam);
        return 0;
    }
    if (message == WM_INPUT_DEVICE_CHANGE) {
        if (capture) capture->reset_baseline();
        return 0;
    }
    if (message == WM_CLOSE) { shutdown_requested = true; return 0; }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool registration_matches(HWND hwnd, bool registered) {
    std::array<RAWINPUTDEVICE, 8> devices{};
    UINT count = static_cast<UINT>(devices.size());
    SetLastError(ERROR_SUCCESS);
    const UINT result = GetRegisteredRawInputDevices(devices.data(), &count, sizeof(RAWINPUTDEVICE));
    const DWORD error = GetLastError();
    // Only this process's own registrations: never handles, device identifiers,
    // other-process metadata, keyboard values or mouse values.
    std::cout << "INPUT_CAPTURE_REGISTRATION_READBACK count=" << count
        << " returned=" << result << " error=" << error << '\n';
    const UINT rows = result == static_cast<UINT>(-1) ? 0 : std::min<UINT>(result, static_cast<UINT>(devices.size()));
    for (UINT i = 0; i < rows; ++i) {
        std::cout << "INPUT_CAPTURE_REGISTRATION_ROW page=" << devices[i].usUsagePage
            << " usage=" << devices[i].usUsage << " flags=" << devices[i].dwFlags << '\n';
    }
    std::cout << std::flush;
    if (result == static_cast<UINT>(-1) || result > devices.size()) return false;
    if (!registered) return result == 0;
    if (result != 2) return false;
    bool mouse{}, keyboard{};
    for (UINT i = 0; i < result; ++i) {
        const auto& device = devices[i];
        if (device.usUsagePage != 1 || (device.usUsage != 2 && device.usUsage != 6) ||
            device.hwndTarget != hwnd || !ic::valid_registration_flags(device.dwFlags)) return false;
        // Actual Windows readback (2026-10-12) returned flags=0x100 for both
        // successful 0x2100 requests. Permit only that omitted DEVNOTIFY bit;
        // NOLEGACY, NOHOTKEYS, EXINPUTSINK and unknown flags remain rejected.
        // Notification delivery/unplug behavior still needs physical verification.
        if (device.usUsage == 2) { if (mouse) return false; mouse = true; }
        else { if (keyboard) return false; keyboard = true; }
    }
    return mouse && keyboard;
}

class RawRegistration {
public:
    explicit RawRegistration(Capture& capture) {
        const HINSTANCE instance = GetModuleHandleW(nullptr);
        WNDCLASSEXW descriptor{};
        descriptor.cbSize = sizeof(descriptor);
        descriptor.hInstance = instance;
        descriptor.lpfnWndProc = window_proc;
        descriptor.lpszClassName = window_class;
        if (!RegisterClassExW(&descriptor)) throw std::runtime_error("window class registration failed");
        class_registered_ = true;
        hwnd_ = CreateWindowExW(0, window_class, L"", 0, 0, 0, 0, 0,
            HWND_MESSAGE, nullptr, instance, &capture);
        if (!hwnd_) { cleanup(); throw std::runtime_error("message-only window creation failed"); }
        const RAWINPUTDEVICE devices[]{{1, 2, registration_flags, hwnd_}, {1, 6, registration_flags, hwnd_}};
        if (!RegisterRawInputDevices(devices, 2, sizeof(RAWINPUTDEVICE))) {
            cleanup(); throw std::runtime_error("Raw Input registration failed");
        }
        devices_registered_ = true;
        if (!registration_matches(hwnd_, true)) {
            cleanup(); throw std::runtime_error("Raw Input registration readback failed");
        }
        std::cout << "INPUT_CAPTURE_REGISTERED classes=2\n" << std::flush;
    }
    ~RawRegistration() { cleanup(); }
    bool cleanup() noexcept {
        if (cleaned_) return cleanup_ok_;
        cleaned_ = true;
        bool unregistered = true;
        if (devices_registered_) {
            const RAWINPUTDEVICE remove[]{{1, 2, RIDEV_REMOVE, nullptr}, {1, 6, RIDEV_REMOVE, nullptr}};
            unregistered = RegisterRawInputDevices(remove, 2, sizeof(RAWINPUTDEVICE)) && registration_matches(hwnd_, false);
            devices_registered_ = false;
            std::cout << "INPUT_CAPTURE_CLEANUP unregistered=" << (unregistered ? "true" : "false") << '\n' << std::flush;
        }
        if (hwnd_) { if (!DestroyWindow(hwnd_)) unregistered = false; hwnd_ = nullptr; }
        if (class_registered_) { if (!UnregisterClassW(window_class, GetModuleHandleW(nullptr))) unregistered = false; class_registered_ = false; }
        cleanup_ok_ = unregistered;
        return cleanup_ok_;
    }
private:
    HWND hwnd_{};
    bool class_registered_{};
    bool devices_registered_{};
    bool cleaned_{};
    bool cleanup_ok_{true};
};

BOOL WINAPI console_handler(DWORD signal) {
    if (signal == CTRL_C_EVENT || signal == CTRL_BREAK_EVENT || signal == CTRL_CLOSE_EVENT ||
        signal == CTRL_SHUTDOWN_EVENT) { shutdown_requested = true; return TRUE; }
    return FALSE;
}

std::uint64_t utc_ms() {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count());
}

int run(const Options& opts) {
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, opts.identity.target_pid));
    FILETIME creation{}, exit{}, kernel{}, user{};
    if (!process.valid() || !GetProcessTimes(process.value, &creation, &exit, &kernel, &user) ||
        filetime_value(creation) != opts.start || !alive(process.value))
        throw std::runtime_error("target process identity/alive check failed");
    EvidenceWriter writer(opts.output);
    Capture capture;
    capture.target_pid = opts.identity.target_pid;
    capture.process = process.value;
    RawRegistration registration(capture);
    ForegroundObserver foreground_observer(capture);
    SetConsoleCtrlHandler(console_handler, TRUE);
    const auto started = Clock::now();
    const auto deadline = started + std::chrono::seconds(opts.seconds);
    auto next_sample = started + std::chrono::milliseconds(50);
    std::uint64_t sequence = 1;
    bool write_error = !writer.write(ic::record_json(opts.identity, "begin", sequence++, utc_ms(), 0, {}));
    std::string reason = write_error ? "write_error" : "duration";
    while (!write_error) {
        auto now = Clock::now();
        if (!alive(process.value)) { reason = "target_exit"; break; }
        if (shutdown_requested || capture.failed) { reason = "shutdown"; break; }
        if (now >= deadline) break;
        capture.update_focus();
        // A flood of WM_INPUT cannot starve absolute duration/focus/snapshots.
        MSG message{};
        for (unsigned i = 0; i < 64 && PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE); ++i) {
            if (message.message == WM_QUIT) { shutdown_requested = true; break; }
            capture.dispatch_time = message.time;
            DispatchMessageW(&message);
            if (Clock::now() >= next_sample || Clock::now() >= deadline) break;
        }
        now = Clock::now();
        if (now >= deadline) break;
        if (!alive(process.value)) { reason = "target_exit"; break; }
        capture.update_focus();
        if (now >= next_sample) {
            const bool was_neutral_pending = capture.state.awaiting_neutral_sample();
            const auto sample = capture.state.sample();
            if (was_neutral_pending) capture.epoch = GetTickCount();
            const auto elapsed = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(now - started).count());
            if (!writer.write(ic::record_json(opts.identity, "sample", sequence++, utc_ms(), elapsed, sample))) {
                write_error = true; reason = "write_error"; break;
            }
            // Fixed 50ms grid; a late tick emits once, never a catch-up burst.
            const auto after_write = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count();
            next_sample = started + std::chrono::milliseconds((after_write / 50 + 1) * 50);
        }
        const HANDLE wait_handle = process.value;
        const auto until_tick = std::chrono::duration_cast<std::chrono::milliseconds>(next_sample - Clock::now()).count();
        const DWORD timeout = static_cast<DWORD>(std::clamp<std::int64_t>(until_tick, 0, 5));
        const DWORD waited = MsgWaitForMultipleObjectsEx(1, &wait_handle, timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (waited == WAIT_FAILED) { capture.failed = true; reason = "shutdown"; break; }
    }
    capture.state.focus(false);
    const bool observer_cleanup = foreground_observer.cleanup();
    const bool cleanup = registration.cleanup();
    SetConsoleCtrlHandler(console_handler, FALSE);
    const auto elapsed = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count());
    // Best effort only when storage failed: never report a complete terminal
    // record unless WriteFile and FlushFileBuffers both succeed.
    const bool end_written = writer.write(ic::record_json(opts.identity, "end", sequence, utc_ms(), elapsed, {}, reason), true);
    if (write_error || !end_written || capture.failed || !cleanup || !observer_cleanup) return 1;
    std::cout << "INPUT_CAPTURE_END reason=" << reason << '\n' << std::flush;
    return 0;
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    try { return run(options(argc, argv)); }
    catch (const std::exception& error) {
        std::cerr << "INPUT_CAPTURE_ERROR " << error.what() << '\n';
        return 1;
    }
}
