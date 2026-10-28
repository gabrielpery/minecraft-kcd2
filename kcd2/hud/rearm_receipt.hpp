#pragma once
#include "rearm_policy.hpp"
#include <array>
#include <charconv>
#include <sstream>

namespace minecome::hud::rearm {
namespace receipt_detail {
inline bool hex(std::string_view value, std::size_t size) {
    return value.size() == size && std::all_of(value.begin(), value.end(), [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}
inline bool valid_owner(const Generation &owner) {
    const auto &id = owner.arm.identity;
    return owner.ordinal && owner.ordinal <= maximum_sessions && hex(id.run, 32) &&
        hex(id.arm_sha256, 64) && id.target_pid && id.producer_pid &&
        id.target_pid != id.producer_pid && id.target_start && id.producer_start;
}
inline bool number(std::string_view value, std::uint64_t &out) {
    if (value.empty()) return false;
    const auto result = std::from_chars(value.data(), value.data() + value.size(), out);
    return result.ec == std::errc{} && result.ptr == value.data() + value.size();
}
inline void identity(std::ostream &out, const Identity &id) {
    out << "RunId=" << id.run << "\nArmSha256=" << id.arm_sha256
        << "\nTargetPid=" << id.target_pid << "\nTargetStartFileTime=" << id.target_start
        << "\nProducerPid=" << id.producer_pid << "\nProducerStartFileTime=" << id.producer_start << '\n';
}
}

// Fixed-size ASCII sidecar from the controller, never a general INI reader.
// A successful parse proves binding/completeness only. The adapter must verify
// the separate verification JSON digest and obtain the native retirement facts.
inline bool parse_cleanup(std::string_view text, const Generation &expected,
                          ControllerCleanup &out, std::string &error) {
    out = {};
    error.clear();
    const auto reject = [&](const char *reason) { error = reason; return false; };
    if (text.empty() || text.size() > 4096) return reject("cleanup_size");
    if (!receipt_detail::valid_owner(expected)) return reject("cleanup_owner");
    for (const unsigned char c : text)
        if ((c < 32 && c != '\r' && c != '\n') || c > 126) return reject("cleanup_encoding");
    constexpr std::array<std::string_view, 12> keys{
        "Schema", "RunId", "ArmSha256", "TargetPid", "TargetStartFileTime", "ProducerPid",
        "ProducerStartFileTime", "VerificationSha256", "Verified", "AimedCleanup", "MovementRestored", "GuestCleanup"};
    std::array<std::string_view, keys.size()> values{};
    std::array<bool, keys.size()> seen{};
    bool header = false;
    while (!text.empty()) {
        const auto end = text.find('\n');
        auto line = text.substr(0, end);
        text = end == text.npos ? std::string_view{} : text.substr(end + 1);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty()) continue;
        if (!header) {
            if (line != "[MineComeRearmCleanup]") return reject("cleanup_section");
            header = true;
            continue;
        }
        const auto equals = line.find('=');
        if (equals == line.npos) return reject("cleanup_line");
        const auto key = std::find(keys.begin(), keys.end(), line.substr(0, equals));
        if (key == keys.end()) return reject("cleanup_key");
        const auto index = static_cast<std::size_t>(key - keys.begin());
        if (seen[index]) return reject("cleanup_duplicate");
        seen[index] = true;
        values[index] = line.substr(equals + 1);
    }
    if (!header || !std::all_of(seen.begin(), seen.end(), [](bool value) { return value; }))
        return reject("cleanup_missing");
    if (values[0] != "1") return reject("cleanup_schema");
    const auto &id = expected.arm.identity;
    if (values[1] != id.run || values[2] != id.arm_sha256) return reject("cleanup_identity");
    std::array<std::uint64_t, 4> numbers{};
    for (std::size_t i = 0; i < numbers.size(); ++i)
        if (!receipt_detail::number(values[3 + i], numbers[i])) return reject("cleanup_number");
    if (numbers[0] != id.target_pid || numbers[1] != id.target_start ||
        numbers[2] != id.producer_pid || numbers[3] != id.producer_start)
        return reject("cleanup_identity");
    if (!receipt_detail::hex(values[7], 64)) return reject("cleanup_digest");
    for (std::size_t i = 8; i < values.size(); ++i)
        if (values[i] != "1") return reject("cleanup_incomplete");
    out = {true, true, true, true, std::string(values[7])};
    return true;
}

inline std::string format_retired(const Generation &owner, const ControllerCleanup &cleanup, Phase phase) {
    if (!receipt_detail::valid_owner(owner) || !receipt_detail::hex(cleanup.verification_sha256, 64) ||
        !cleanup.verified || !cleanup.aimed_cleanup || !cleanup.movement_restored || !cleanup.guest_cleanup ||
        !((phase == Phase::idle && owner.ordinal == 1) ||
          (phase == Phase::exhausted && owner.ordinal == maximum_sessions))) return {};
    std::ostringstream out;
    out << "[MineComeRearmRetired]\nSchema=1\n";
    receipt_detail::identity(out, owner.arm.identity);
    out << "VerificationSha256=" << cleanup.verification_sha256 << "\nGeneration=" << owner.ordinal
        << "\nState=" << (phase == Phase::idle ? "idle" : "exhausted") << '\n';
    return out.str();
}
} // namespace minecome::hud::rearm
