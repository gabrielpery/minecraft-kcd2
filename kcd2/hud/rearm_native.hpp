#pragma once
#include "input_diagnostics.hpp"
#include "selective_capture_api.hpp"
#include <string_view>

namespace minecome::hud::rearm {
// Cleanup cannot turn an input fault into a reusable session.
inline bool normal_input_close(input::CloseCause cause, std::string_view reason) {
    return (cause == input::CloseCause::activation_expired || cause == input::CloseCause::second_f8 ||
            cause == input::CloseCause::session_end) &&
        (reason == "ownership_closed" || reason == "image_channel_closed");
}
// This snapshot must come from API2 release(window, token), which checks both
// identities. query() does not check its token and cannot establish this proof.
inline bool capture_released(selective::Result result, const selective::Snapshot &snapshot,
                             std::uint64_t token, std::uint64_t captured_generation) {
    return result == selective::Result::ok && token && snapshot.token == token &&
        captured_generation && snapshot.generation >= captured_generation &&
        !(snapshot.flags & (selective::active | selective::draining));
}
} // namespace minecome::hud::rearm
