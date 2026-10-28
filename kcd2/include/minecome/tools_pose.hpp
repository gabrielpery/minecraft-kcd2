// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <minecome/protocol.hpp>
#include <optional>
#include <string>
#include <string_view>

namespace minecome {
enum class FovUnit { radians, degrees };
struct ToolsPose {
    protocol::Pose pose;
    bool has_player{};
};
// Parses only MineCome's own fixed schema-1 diagnostic log format.
// KCD world is +X right, +Y forward, +Z up. The wire camera's local axes are
// +X right, +Y up, -Z forward. Scale remains uncalibrated.
std::optional<ToolsPose> parse_tools_pose(std::string_view line, FovUnit unit);

// Exact record emitted by the existing run-bound walking camera sampler.
// Engine time is not UTC; callers additionally require fresh append-only bytes.
struct PhysicalToolsPose {
    ToolsPose sample;
    std::string run;
    std::uint64_t sequence{};
    double sampled_engine_seconds{};
};
std::optional<PhysicalToolsPose> parse_physical_tools_pose(std::string_view line);
enum class PhysicalPoseDecision { accepted, foreign_run, stale_batch, replayed_or_regressed };
class PhysicalPoseCursor {
    std::string run_;
    std::uint64_t last_sequence_{};
    double last_engine_seconds_{-1};
public:
    explicit PhysicalPoseCursor(std::string run);
    // Even a discarded stale record spends its sequence/clock watermark: copying
    // it into a later fresh append must never renew authority.
    PhysicalPoseDecision observe(const PhysicalToolsPose& sample,bool fresh_batch);
};
}
