// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone ABI/initialization test. This does not load or emulate game code.
#include <KCSE/KCSEAPI.h>
#include <Windows.h>

#include <filesystem>
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
class Messaging final : public KCSE::IMessagingInterface {
public:
    EventCallback callback{};
    uint32_t GetInterfaceVersion() const override { return kInterfaceVersion; }
    bool RegisterListener(EventCallback value) override { callback = value; return value != nullptr; }
    bool RegisterListener(const char*, EventCallback value) override { return RegisterListener(value); }
    bool Dispatch(uint32_t type, void* data, uint32_t size, const char*) override {
        if (!callback) return false;
        KCSE::Message message{"KCSE", type, size, data};
        callback(&message);
        return true;
    }
};

class Interface final : public KCSE::IKCSEInterface {
public:
    mutable Messaging messaging;
    uint32_t game_version{0x01050600};
    uint32_t GetKCSEVersion() const override { return 1; }
    uint32_t GetGameVersion() const override { return game_version; }
    uint32_t GetReleaseIndex() const override { return 0; }
    KCSE::PluginHandle GetPluginHandle() const override { return 1; }
    const KCSE::PluginInfo* GetPluginInfo(const char*) const override { return nullptr; }
    void* QueryInterface(uint32_t id) const override {
        return id == KCSE::kInterface_Messaging ? &messaging : nullptr;
    }
};

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        require(argc == 3, "usage: kcse_adapter_smoke <plugin DLL> <test directory>");
        const auto fixture = std::filesystem::absolute(argv[2]);
        std::filesystem::create_directories(fixture / "config");
        std::ofstream(fixture / "config" / "bridge.token") << std::string(64, 'a') << '\n';
        SetEnvironmentVariableW(L"MINECOME_HOME", fixture.c_str());
        SetEnvironmentVariableW(L"MINECOME_TOKEN_FILE", nullptr);
        SetEnvironmentVariableW(L"MINECOME_LOG_FILE", nullptr);
        SetEnvironmentVariableW(L"MINECOME_PORT", L"38769");
        const auto plugin = LoadLibraryW(argv[1]);
        require(plugin != nullptr, "cannot load compiled adapter DLL");
        auto* version = reinterpret_cast<KCSE::PluginVersionData*>(GetProcAddress(plugin, "KCSEPlugin_Version"));
        auto load = reinterpret_cast<KCSE::PluginLoadFn>(GetProcAddress(plugin, "KCSEPlugin_Load"));
        auto shutdown = reinterpret_cast<void(*)()>(GetProcAddress(plugin, "MineCome_Shutdown"));
        require(version && load && shutdown, "required plugin exports missing");
        require(version->dataVersion == 1 && version->compatibleGameVersions[0] == 0x01050600,
            "version export does not restrict the game ABI");
        Interface interface;
        interface.game_version = 0x01050700;
        require(!load(&interface), "adapter accepted an unsupported game version");
        interface.game_version = 0x01050600;
        SetEnvironmentVariableW(L"MINECOME_PORT", L"65536");
        require(!load(&interface), "adapter accepted an out-of-range port");
        SetEnvironmentVariableW(L"MINECOME_PORT", L"38769junk");
        require(!load(&interface), "adapter accepted a malformed port");
        SetEnvironmentVariableW(L"MINECOME_PORT", L"38769");
        const auto missing_token = fixture / "config" / "missing-token.fixture";
        SetEnvironmentVariableW(L"MINECOME_TOKEN_FILE", missing_token.c_str());
        require(!load(&interface), "adapter initialized without its credential file");
        SetEnvironmentVariableW(L"MINECOME_TOKEN_FILE", nullptr);
        require(load(&interface), "supported adapter failed to initialize its real transport");
        require(interface.messaging.Dispatch(KCSE::IMessagingInterface::kMessage_DataLoaded, nullptr, 0, nullptr),
            "lifecycle listener was not registered");
        const auto shutdown_start = std::chrono::steady_clock::now();
        shutdown();
        require(std::chrono::steady_clock::now() - shutdown_start < std::chrono::seconds(2),
            "adapter shutdown exceeded its bounded stop expectation");
        std::ifstream diagnostic(fixture / "runtime" / "logs" / "kcse.log.kcse.log");
        const std::string contents((std::istreambuf_iterator<char>(diagnostic)), std::istreambuf_iterator<char>());
        require(contents.find("DataLoaded received") != std::string::npos && contents.find("Transport stopped") != std::string::npos,
            "initialization/lifecycle/shutdown evidence missing from diagnostic log");
        std::cout << "KCSE adapter exports, version/port/token rejection, transport startup, lifecycle and bounded shutdown passed.\n";
        std::cout << "Standalone verification only; KCD2 was not launched.\n";
        // Successful plugins pin their DLL; callbacks therefore cannot outlive code.
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
