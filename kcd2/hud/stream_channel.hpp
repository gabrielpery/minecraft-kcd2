#pragma once
#include "stream_contract.hpp"
#include <Windows.h>
#include <memory>
#include <vector>

namespace minecome::hud::stream {
struct Handle {
    HANDLE value = nullptr;
    explicit Handle(HANDLE v = nullptr) : value(v) {}
    ~Handle() { reset(); }
    Handle(const Handle &) = delete;
    Handle &operator=(const Handle &) = delete;
    explicit operator bool() const { return value && value != INVALID_HANDLE_VALUE; }
    void reset(HANDLE next = nullptr) { if (*this) CloseHandle(value); value = next; }
};
std::uint64_t utc_ms() noexcept;
std::uint64_t steady_ms() noexcept;
std::uint64_t process_start(HANDLE process = GetCurrentProcess()) noexcept;
std::wstring module_path(HMODULE module = nullptr);
// Fixed local regular files only; bounded cancellable worker reads. No render use.
bool read_file(const std::wstring &path, std::uint64_t maximum, HANDLE stop,
               std::vector<std::uint8_t> *bytes, std::string *sha256);
struct Frame {
    Header header;
    std::uint64_t observation = 0;
    std::vector<std::uint8_t> premultiplied;
};
enum class Poll { busy, waiting, unchanged, frame, closed, failed };
class Channel {
public:
    Channel() = default;
    ~Channel();
    Channel(const Channel &) = delete;
    Channel &operator=(const Channel &) = delete;
    bool open(const Identity &identity);
    Poll poll(std::shared_ptr<const Frame> &next);
    bool live() const;
    bool fresh() const;
    const std::string &reason() const { return validator_.reason(); }
    void close();
private:
    Handle mapping_, mutex_, producer_, target_;
    const std::uint8_t *mapped_ = nullptr;
    Validator validator_;
    std::vector<std::uint8_t> snapshot_;
    bool opened_ = false;
};
} // namespace minecome::hud::stream
