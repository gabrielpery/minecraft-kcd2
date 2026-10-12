// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <minecome/protocol.hpp>
#include <optional>
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
}
