#pragma once
// Original MineCome static HUD proof contract; no engine offsets or game calls.
#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace minecome::hud {
inline constexpr std::uint64_t max_lease_ms = 45000;
inline constexpr std::size_t max_config_bytes = 32768;
inline constexpr std::size_t max_frame_bytes = 1920u * 1080u * 4u;
struct FrameSpec { std::string path, sha256; };
struct Arm {
    std::string run;
    std::uint32_t target_pid = 0, frame_count = 0, width = 0, height = 0;
    std::uint64_t target_start = 0, expires_utc_ms = 0;
    std::array<FrameSpec, 3> frames{};
};
bool parse_arm(std::string_view text, std::uint32_t pid, std::uint64_t start,
               std::uint64_t now_utc_ms, Arm &out, std::string &error);
std::size_t byte_count(std::uint32_t width, std::uint32_t height) noexcept;
bool premultiply_rgba(std::span<std::uint8_t> pixels, std::uint32_t width,
                      std::uint32_t height) noexcept;
struct Rect { float x = 0, y = 0, width = 0, height = 0; };
// Full source canvas, centered with preserved aspect. Integer enlargement where
// possible; shrinking uses point sampling with a bounded aspect-preserving fit.
Rect fit_rect(std::uint32_t source_width, std::uint32_t source_height,
              std::uint32_t target_width, std::uint32_t target_height) noexcept;
enum class TeardownMode { live_effects, after_runtime_reset };
struct TeardownPlan {
    bool invalidate_effect_handles = false;
    bool hide_effect = false;
    bool erase_semantic_cache = false;
    bool destroy_owned_resources = false;
};
// ReShade 6.8.0 invokes destroy_effect_runtime AFTER destroying all effects.
// The public runtime object/cache and owned device resources still exist.
TeardownPlan teardown_plan(TeardownMode mode, bool cached_effect,
                           bool bound, bool owned_resources) noexcept;
class Lease {
public:
    bool accept(const Arm &arm, std::uint64_t utc_ms, std::uint64_t steady_ms) noexcept;
    bool live(std::uint64_t utc_ms, std::uint64_t steady_ms) const noexcept;
    std::uint32_t frame_index(std::uint64_t steady_ms) const noexcept;
    bool consumed() const noexcept { return consumed_; }
private:
    bool consumed_ = false;
    std::uint64_t start_steady_ = 0, deadline_steady_ = 0, expires_utc_ = 0;
    std::uint32_t count_ = 0;
};
} // namespace minecome::hud
