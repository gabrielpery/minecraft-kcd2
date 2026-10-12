#pragma once
// Original bounded HUD transport; no game APIs or engine addresses.
#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace minecome::hud::stream {
inline constexpr std::size_t header_bytes = 256;
inline constexpr std::size_t pixel_capacity = 1920u * 1080u * 4u;
inline constexpr std::size_t mapping_bytes = header_bytes + pixel_capacity;
inline constexpr std::size_t max_arm_bytes = 4096;
inline constexpr std::uint64_t max_lease_ms = 180000, fresh_ms = 500;
struct Identity {
    std::string run;
    std::uint32_t producer_pid = 0, target_pid = 0;
    std::uint64_t producer_start = 0, target_start = 0, expires_utc_ms = 0;
};
struct Header {
    std::uint64_t sequence = 0, capture_utc_ms = 0;
    std::uint32_t width = 0, height = 0, pitch = 0, bytes = 0;
    std::uint32_t state = 0, selected = 0, screen = 0;
};
bool valid_identity(const Identity &identity) noexcept;
bool parse_arm(std::string_view text, std::uint32_t target_pid, std::uint64_t target_start,
               std::uint64_t utc, Identity &out, std::string &error);
enum class Result { waiting, unchanged, frame, closed, invalid, expired };
class Validator {
public:
    bool start(const Identity &identity, std::uint64_t utc, std::uint64_t steady);
    Result accept(std::span<const std::uint8_t> header, std::uint64_t utc,
                  std::uint64_t steady, Header &out);
    bool live(std::uint64_t utc, std::uint64_t steady) const noexcept;
    bool fresh(std::uint64_t utc, std::uint64_t steady) const noexcept;
    const std::string &reason() const noexcept { return reason_; }
    std::uint64_t observed() const noexcept { return observed_; }
    std::uint64_t sequence() const noexcept { return sequence_; }
    const Identity &identity() const noexcept { return identity_; }
    void invalidate(std::string_view reason);
private:
    Identity identity_;
    bool consumed_ = false, terminal_ = false, have_frame_ = false;
    std::uint64_t begun_ = 0, deadline_ = 0, sequence_ = 0, observed_ = 0;
    std::uint32_t width_ = 0, height_ = 0;
    std::string reason_;
};
bool uploaded_fresh(std::uint64_t observation, std::uint64_t now) noexcept;
} // namespace minecome::hud::stream
