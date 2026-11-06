#include "stream_channel.hpp"
#include "hud_contract.hpp"
#include <bcrypt.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>

namespace minecome::hud::stream {
std::uint64_t utc_ms() noexcept {
    FILETIME time{}; GetSystemTimeAsFileTime(&time);
    const auto ticks = (std::uint64_t(time.dwHighDateTime) << 32) | time.dwLowDateTime;
    return ticks >= 116444736000000000ULL ? (ticks-116444736000000000ULL)/10000 : 0;
}
std::uint64_t steady_ms() noexcept { return GetTickCount64(); }
std::uint64_t process_start(HANDLE process) noexcept {
    FILETIME creation{}, exit{}, kernel{}, user{};
    if (!GetProcessTimes(process, &creation, &exit, &kernel, &user)) return 0;
    return (std::uint64_t(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
}
std::wstring module_path(HMODULE module) {
    std::wstring path(32768, L'\0');
    const DWORD n = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!n || n >= path.size()) return {};
    path.resize(n); return path;
}
namespace {
struct Hash {
    BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE value = nullptr;
    Hash() {
        if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0 &&
            BCryptCreateHash(algorithm, &value, nullptr, 0, nullptr, 0, 0) < 0) value = nullptr;
    }
    ~Hash() { if (value) BCryptDestroyHash(value); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
    bool add(std::span<const std::uint8_t> data) {
        return value && BCryptHashData(value, const_cast<PUCHAR>(data.data()), static_cast<ULONG>(data.size()), 0) >= 0;
    }
    std::string finish() {
        std::array<std::uint8_t,32> digest{};
        if (!value || BCryptFinishHash(value, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) return {};
        constexpr char hex[] = "0123456789abcdef"; std::string result;
        for (auto b : digest) { result += hex[b >> 4]; result += hex[b & 15]; }
        return result;
    }
};
}
bool read_file(const std::wstring &path, std::uint64_t maximum, HANDLE stop,
               std::vector<std::uint8_t> *bytes, std::string *sha256) {
    if (path.size() < 3 || path[1] != L':' || (path[2] != L'\\' && path[2] != L'/')) return false;
    wchar_t drive[]{path[0],L':',L'\\',0};
    if (GetDriveTypeW(drive) != DRIVE_FIXED || !stop || WaitForSingleObject(stop,0) != WAIT_TIMEOUT) return false;
    Handle file(CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED|FILE_FLAG_SEQUENTIAL_SCAN|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
    BY_HANDLE_FILE_INFORMATION info{}; LARGE_INTEGER length{};
    if (!file || !GetFileInformationByHandle(file.value,&info) || !GetFileSizeEx(file.value,&length) ||
        (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)) ||
        length.QuadPart <= 0 || std::uint64_t(length.QuadPart) > maximum) return false;
    Handle completed(CreateEventW(nullptr,TRUE,FALSE,nullptr));
    if (!completed) return false;
    if (bytes) { bytes->clear(); bytes->reserve(static_cast<std::size_t>(length.QuadPart)); }
    Hash hash; if (sha256 && !hash.value) return false;
    std::array<std::uint8_t,65536> chunk{};
    for (std::uint64_t offset = 0; offset < std::uint64_t(length.QuadPart);) {
        if (WaitForSingleObject(stop,0) != WAIT_TIMEOUT) return false;
        OVERLAPPED io{}; io.Offset = static_cast<DWORD>(offset); io.OffsetHigh = static_cast<DWORD>(offset >> 32); io.hEvent = completed.value;
        ResetEvent(completed.value);
        const auto want = static_cast<DWORD>(std::min<std::uint64_t>(chunk.size(), std::uint64_t(length.QuadPart)-offset));
        DWORD got = 0;
        if (!ReadFile(file.value,chunk.data(),want,nullptr,&io)) {
            if (GetLastError() != ERROR_IO_PENDING) return false;
            HANDLE events[]{stop,completed.value};
            if (WaitForMultipleObjects(2,events,FALSE,2000) != WAIT_OBJECT_0+1) {
                CancelIoEx(file.value,&io); GetOverlappedResult(file.value,&io,&got,TRUE); return false;
            }
        }
        if (!GetOverlappedResult(file.value,&io,&got,FALSE) || got != want) return false;
        if (bytes) bytes->insert(bytes->end(),chunk.begin(),chunk.begin()+got);
        if (sha256 && !hash.add(std::span(chunk.data(),got))) return false;
        offset += got;
    }
    if (sha256) { *sha256 = hash.finish(); if (sha256->empty()) return false; }
    return WaitForSingleObject(stop,0) == WAIT_TIMEOUT;
}
Channel::~Channel() { close(); }
void Channel::close() {
    if (mapped_) { UnmapViewOfFile(mapped_); mapped_ = nullptr; }
    mapping_.reset(); mutex_.reset(); producer_.reset(); target_.reset(); opened_ = false;
}
bool Channel::open(const Identity &id) {
    if (!validator_.start(id,utc_ms(),steady_ms())) return false;
    producer_.reset(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,id.producer_pid));
    target_.reset(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,id.target_pid));
    if (!producer_ || !target_ || process_start(producer_.value) != id.producer_start ||
        process_start(target_.value) != id.target_start) {
        validator_.invalidate("process_identity"); close(); return false;
    }
    const auto suffix = std::wstring(id.run.begin(),id.run.end());
    mapping_.reset(OpenFileMappingW(FILE_MAP_READ,FALSE,(L"Local\\MineComeHud_"+suffix).c_str()));
    mutex_.reset(OpenMutexW(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,(L"Local\\MineComeHudLock_"+suffix).c_str()));
    if (!mapping_ || !mutex_) { validator_.invalidate("channel_missing"); close(); return false; }
    const auto size = mapping_for_schema(id.schema);
    mapped_ = static_cast<const std::uint8_t *>(MapViewOfFile(mapping_.value,FILE_MAP_READ,0,0,size));
    if (!mapped_) { validator_.invalidate("channel_mapping_size"); close(); return false; }
    snapshot_.resize(size); opened_ = true; return true;
}
bool Channel::live() const { return opened_ && validator_.live(utc_ms(),steady_ms()); }
bool Channel::fresh() const { return opened_ && validator_.fresh(utc_ms(),steady_ms()); }
Poll Channel::poll(std::shared_ptr<const Frame> &next) {
    next.reset();
    auto fail = [&](std::string_view reason) { validator_.invalidate(reason); return Poll::failed; };
    if (!opened_) return fail("channel_not_open");
    if (!validator_.live(utc_ms(),steady_ms())) return fail("expired");
    if (WaitForSingleObject(producer_.value,0) != WAIT_TIMEOUT) return fail("producer_exited");
    if (WaitForSingleObject(target_.value,0) != WAIT_TIMEOUT) return fail("target_exited");
    const DWORD wait = WaitForSingleObject(mutex_.value,5);
    if (wait == WAIT_TIMEOUT) return Poll::busy;
    if (wait == WAIT_ABANDONED) { ReleaseMutex(mutex_.value); return fail("mutex_abandoned"); }
    if (wait != WAIT_OBJECT_0) return fail("mutex_failed");
    // Copy and validate the small private header before trusting its payload
    // length. The mutex makes all three planes one coherent publication.
    // Pixel validation/conversion happens after releasing ownership.
    std::memcpy(snapshot_.data(),mapped_,header_bytes);
    Header header;
    Result accepted;
    try {
        accepted = validator_.accept(std::span(snapshot_.data(),header_bytes),utc_ms(),steady_ms(),header);
        if (accepted == Result::frame)
            std::memcpy(snapshot_.data()+header_bytes,mapped_+header_bytes,header.bytes);
    } catch (...) { ReleaseMutex(mutex_.value); throw; }
    if (!ReleaseMutex(mutex_.value)) return fail("mutex_release_failed");
    switch (accepted) {
    case Result::waiting: return Poll::waiting;
    case Result::unchanged: return Poll::unchanged;
    case Result::closed: return Poll::closed;
    case Result::invalid: case Result::expired: return Poll::failed;
    case Result::frame: break;
    }
    auto frame = std::make_shared<Frame>(); frame->header = header; frame->observation = validator_.observed();
    frame->premultiplied.assign(snapshot_.begin()+header_bytes,snapshot_.begin()+header_bytes+header.bytes);
    auto payload=std::span(frame->premultiplied);const auto plane=std::size_t(header.pitch)*header.height;
    if (!minecome::hud::premultiply_rgba(payload.first(plane),header.width,header.height)) return fail("premultiply_failed");
    if (header.format == 2) {
        if (!minecome::hud::premultiply_rgba(payload.subspan(plane,plane),header.width,header.height)) return fail("premultiply_failed");
        // Do not reinterpret depth as RGBA/alpha. Reject malformed depth rather
        // than letting NaN/Inf or out-of-range samples affect native visibility.
        for (std::size_t at=plane*2;at<payload.size();at+=4) {
            std::uint32_t bits=0;for(unsigned i=0;i<4;++i)bits|=std::uint32_t(payload[at+i])<<(i*8);
            const float depth=std::bit_cast<float>(bits);
            if(!std::isfinite(depth)||depth<0.f||depth>1.f)return fail("depth_sample_invalid");
        }
    }
    // A dead producer cannot gain an extra publication while conversion ran.
    if (WaitForSingleObject(producer_.value,0) != WAIT_TIMEOUT) return fail("producer_exited");
    if (!validator_.live(utc_ms(),steady_ms())) return fail("expired");
    next = std::move(frame); return Poll::frame;
}
} // namespace minecome::hud::stream
