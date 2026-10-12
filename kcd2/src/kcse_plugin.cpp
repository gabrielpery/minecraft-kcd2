// SPDX-License-Identifier: GPL-3.0-or-later
// This adapter uses the real GPLv3 KCSE API. Engine access stays disabled until
// its loader and exact 1.5.6 Steam address library have been verified.
#include <KCSE/KCSEAPI.h>
#include <minecome/bridge.hpp>

#include <Windows.h>

#include <atomic>
#include <charconv>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>

namespace {
constexpr std::uint32_t supported_game_version = 0x01050600;
std::atomic<bool> active{false};
std::mutex adapter_mutex;
std::mutex diagnostic_mutex;
std::filesystem::path diagnostic_path;

// KCSE has no unload callback. The plugin pins its module after a successful
// start and uses explicit shutdown outside DllMain for controlled host tests.
// The heap-owned bridge has no destructor running under the Windows loader lock.
minecome::Bridge* bridge = nullptr;

std::filesystem::path environment_path(const wchar_t* variable) {
    const auto length = GetEnvironmentVariableW(variable, nullptr, 0);
    if (!length) return {};
    std::wstring value(length, L'\0');
    const auto written = GetEnvironmentVariableW(variable, value.data(), length);
    if (!written || written >= length) return {};
    value.resize(written);
    return std::filesystem::path(value);
}

void diagnostic(const char* message) {
    OutputDebugStringA(message);
    OutputDebugStringA("\n");
    std::lock_guard lock(diagnostic_mutex);
    if (diagnostic_path.empty()) return;
    std::ofstream output(diagnostic_path, std::ios::app);
    output << "[MineCome KCSE] " << message << '\n';
}

void lifecycle(KCSE::Message* message) {
    if (!message || !active.load()) return;
    if (message->type == KCSE::IMessagingInterface::kMessage_DataLoaded) {
        diagnostic("DataLoaded received; native engine pose reads disabled (address map unavailable)");
    } else if (message->type == KCSE::IMessagingInterface::kMessage_LoadGame) {
        diagnostic("LoadGame received; transport remains active");
    }
}
} // namespace

KCSE_EXPORT KCSE::PluginVersionData KCSEPlugin_Version = {
    KCSE::PluginVersionData::kDataVersion,
    1,
    "MineCome",
    "MineCome contributors",
    {supported_game_version},
    1,
    KCSE::PluginVersionData::kVersionIndependent_None
};

KCSE_EXPORT bool KCSEPlugin_Load(const KCSE::IKCSEInterface* kcse) {
    std::lock_guard adapter_lock(adapter_mutex);
    try {
    if (!kcse || kcse->GetGameVersion() != supported_game_version ||
        kcse->GetKCSEVersion() < 1) {
        diagnostic("Refusing incompatible game/KCSE version");
        return false;
    }
    if (active.load()) return true;

    const auto home = environment_path(L"MINECOME_HOME");
    auto token_file = environment_path(L"MINECOME_TOKEN_FILE");
    auto log_file = environment_path(L"MINECOME_LOG_FILE");
    if (token_file.empty() && !home.empty()) token_file = home / "config" / "bridge.token";
    if (log_file.empty() && !home.empty()) log_file = home / "runtime" / "logs" / "kcse.log";
    if (token_file.empty() || log_file.empty() || !token_file.is_absolute() || !log_file.is_absolute()) {
        diagnostic("Set absolute MINECOME_HOME or MINECOME_TOKEN_FILE and MINECOME_LOG_FILE before launch");
        return false;
    }
    {
        std::lock_guard diagnostic_lock(diagnostic_mutex);
        diagnostic_path = log_file;
        diagnostic_path += L".kcse.log";
    }

    std::uint16_t port = 38765;
    const auto port_text = environment_path(L"MINECOME_PORT").string();
    if (!port_text.empty()) {
        unsigned parsed = 0;
        const auto result = std::from_chars(port_text.data(), port_text.data() + port_text.size(), parsed);
        if (result.ec != std::errc{} || result.ptr != port_text.data() + port_text.size() || parsed == 0 || parsed > 65535) {
            diagnostic("MINECOME_PORT must be an integer between 1 and 65535");
            return false;
        }
        port = static_cast<std::uint16_t>(parsed);
    }

    auto* messaging = kcse->GetMessagingInterface();
    if (!messaging || messaging->GetInterfaceVersion() != KCSE::IMessagingInterface::kInterfaceVersion) {
        diagnostic("Required KCSE messaging interface is unavailable");
        return false;
    }

        if (!bridge) bridge = new minecome::Bridge();
        if (!bridge->start(token_file, log_file, port, "MineCome KCSE/0.1.0")) {
            diagnostic("Transport could not start; check token and bridge log");
            return false;
        }
        HMODULE pinned_module = nullptr;
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<const wchar_t*>(&KCSEPlugin_Load), &pinned_module)) {
            bridge->stop();
            diagnostic("Could not pin plugin module for transport lifetime");
            return false;
        }
        KCSE::Init(kcse);
        if (!messaging->RegisterListener(lifecycle)) {
            bridge->stop();
            diagnostic("Could not register the lifecycle listener");
            return false;
        }
        active.store(true);
        diagnostic("Initialized version-gated KCSE transport; no engine pointers or hooks used by adapter");
        return true;
    } catch (...) {
        if (bridge) bridge->stop();
        diagnostic("Transport initialization failed; see bridge log");
        return false;
    }
}

// For a standalone verification harness and orderly explicit shutdown only.
// KCSE itself currently provides no shutdown lifecycle message.
KCSE_EXPORT void MineCome_Shutdown() {
    std::lock_guard adapter_lock(adapter_mutex);
    active.store(false);
    if (bridge) bridge->stop();
    diagnostic("Transport stopped");
}
