// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <minecome/protocol.hpp>
#include <optional>
#include <string>
#include <string_view>

namespace minecome {
// A transient translated display island, not shared-world calibration.
struct StoneAlignment {
    protocol::Vec3 minecraft_anchor, kcd_anchor;
    static std::optional<StoneAlignment> create(const protocol::Pose& minecraft,
                                               const protocol::Pose& kcd);
    std::optional<protocol::Vec3> map(const protocol::BlockEvent&) const;
};
struct StoneReceipt {
    bool block{};
    std::uint64_t session{}, sequence{};
    std::uint32_t operation{};
    std::uint32_t owned_count{},pending_count{};
    std::string event, result;
};
std::optional<StoneReceipt> parse_stone_receipt(std::string_view line);
std::optional<protocol::StoneInputRequest> parse_stone_input_intent(std::string_view line);
std::string stone_event_command(std::uint64_t session, std::uint64_t sequence,
                                const protocol::BlockEvent&, protocol::Vec3 origin);
std::string stone_session_command(std::string_view action, std::uint64_t session);
}
