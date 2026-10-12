#include "stream_contract.hpp"
#include <algorithm>
#include <charconv>
#include <limits>
#include <map>

namespace minecome::hud::stream {
namespace {
bool token(std::string_view value) {
    return value.size() == 32 && std::all_of(value.begin(), value.end(), [](char c) {
        return c >= '0' && c <= '9' || c >= 'a' && c <= 'f';
    });
}
template<class T> bool number(std::string_view value, T &out) {
    if (value.empty() || value.front() < '0' || value.front() > '9') return false;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), out);
    return parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size();
}
std::string_view trim(std::string_view s) {
    while (!s.empty() && (s.front() == ' ' || s.front() == '\t' || s.front() == '\r')) s.remove_prefix(1);
    while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\r')) s.remove_suffix(1);
    return s;
}
std::uint32_t u32(std::span<const std::uint8_t> h, std::size_t at) {
    std::uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value |= std::uint32_t(h[at+i]) << (i*8);
    return value;
}
std::uint64_t u64(std::span<const std::uint8_t> h, std::size_t at) {
    std::uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value |= std::uint64_t(h[at+i]) << (i*8);
    return value;
}
}
bool valid_identity(const Identity &id) noexcept {
    return token(id.run) && id.producer_pid && id.target_pid && id.producer_start &&
        id.target_start && id.expires_utc_ms;
}
bool parse_arm(std::string_view text, std::uint32_t target_pid, std::uint64_t target_start,
               std::uint64_t utc, Identity &out, std::string &error) {
    out = {}; error.clear();
    auto fail = [&](std::string_view why) { error = why; return false; };
    if (text.empty() || text.size() > max_arm_bytes || text.find('\0') != text.npos) return fail("config_size_or_nul");
    std::map<std::string, std::string> fields;
    bool section = false;
    while (!text.empty()) {
        const auto newline = text.find('\n');
        auto line = trim(text.substr(0, newline));
        text = newline == text.npos ? std::string_view{} : text.substr(newline+1);
        if (line.empty()) continue;
        if (!section) {
            if (line != "[HudStream]") return fail("config_section");
            section = true; continue;
        }
        const auto equals = line.find('=');
        if (equals == line.npos) return fail("config_field");
        const auto key = trim(line.substr(0, equals)), value = trim(line.substr(equals+1));
        if (key != "Schema" && key != "Run" && key != "TargetPid" && key != "TargetStart" &&
            key != "ProducerPid" && key != "ProducerStart" && key != "ExpiresUtcMs") return fail("config_unknown");
        if (value.empty() || !fields.emplace(std::string(key), std::string(value)).second) return fail("config_duplicate_or_empty");
    }
    if (!section || fields.size() != 7 || fields["Schema"] != "1") return fail("config_schema_or_missing");
    Identity id; id.run = fields["Run"];
    if (!number(fields["TargetPid"], id.target_pid) || !number(fields["ProducerPid"], id.producer_pid) ||
        !number(fields["TargetStart"], id.target_start) || !number(fields["ProducerStart"], id.producer_start) ||
        !number(fields["ExpiresUtcMs"], id.expires_utc_ms) || !valid_identity(id)) return fail("config_identity");
    if (id.target_pid != target_pid || id.target_start != target_start) return fail("config_target");
    if (id.expires_utc_ms <= utc || id.expires_utc_ms-utc > max_lease_ms) return fail("config_expiry");
    out = std::move(id); return true;
}
bool Validator::start(const Identity &id, std::uint64_t utc, std::uint64_t steady) {
    if (consumed_) return false;
    consumed_ = true;
    if (!valid_identity(id) || id.expires_utc_ms <= utc || id.expires_utc_ms-utc > max_lease_ms ||
        steady > std::numeric_limits<std::uint64_t>::max()-(id.expires_utc_ms-utc)) {
        invalidate("session_identity_or_expiry"); return false;
    }
    identity_ = id; begun_ = steady; deadline_ = steady+(id.expires_utc_ms-utc); return true;
}
bool Validator::live(std::uint64_t utc, std::uint64_t steady) const noexcept {
    return consumed_ && !terminal_ && utc < identity_.expires_utc_ms && steady >= begun_ && steady < deadline_;
}
bool uploaded_fresh(std::uint64_t observation, std::uint64_t now) noexcept {
    return now >= observation && now-observation <= fresh_ms;
}
bool Validator::fresh(std::uint64_t utc, std::uint64_t steady) const noexcept {
    return have_frame_ && live(utc, steady) && uploaded_fresh(observed_, steady);
}
void Validator::invalidate(std::string_view reason) { terminal_ = true; reason_ = reason; }
Result Validator::accept(std::span<const std::uint8_t> bytes, std::uint64_t utc,
                         std::uint64_t steady, Header &out) {
    out = {};
    if (terminal_) return Result::invalid;
    if (!live(utc, steady)) { invalidate("expired"); return Result::expired; }
    auto bad = [&](std::string_view why) { invalidate(why); return Result::invalid; };
    if (bytes.size() != header_bytes) return bad("header_length");
    constexpr std::string_view magic = "MCHUDS01";
    if (!std::equal(magic.begin(), magic.end(), bytes.begin()) || u32(bytes,8) != 1 || u32(bytes,12) != header_bytes)
        return bad("header_magic_or_schema");
    if (!std::equal(identity_.run.begin(), identity_.run.end(), bytes.begin()+16) ||
        u32(bytes,48) != identity_.producer_pid || u32(bytes,52) != identity_.target_pid ||
        u64(bytes,56) != identity_.producer_start || u64(bytes,64) != identity_.target_start ||
        u64(bytes,72) != identity_.expires_utc_ms) return bad("header_identity");
    if (std::any_of(bytes.begin()+128, bytes.end(), [](auto b) { return b != 0; })) return bad("header_reserved");
    Header h; h.sequence = u64(bytes,80); h.capture_utc_ms = u64(bytes,88);
    h.width = u32(bytes,96); h.height = u32(bytes,100); h.pitch = u32(bytes,104); h.bytes = u32(bytes,108);
    h.state = u32(bytes,116); h.selected = u32(bytes,120); h.screen = u32(bytes,124);
    if (u32(bytes,112) != 1 || h.state > 2 || h.selected > 8 || h.screen > 1) return bad("header_format_or_state");
    if (h.state == 2) {
        if (!h.sequence) {
            if (h.capture_utc_ms || h.width || h.height || h.pitch || h.bytes || h.selected || h.screen)
                return bad("closed_waiting_nonzero");
        } else if (!h.capture_utc_ms || !h.width || h.width > 1920 || !h.height || h.height > 1080 ||
                   h.pitch != h.width*4 || h.bytes != h.pitch*h.height) return bad("closed_frame_dimensions");
        invalidate("closed"); out = h; return Result::closed;
    }
    if (h.state == 0) {
        if (have_frame_) return bad("waiting_after_frame");
        if (h.sequence || h.capture_utc_ms || h.width || h.height || h.pitch || h.bytes || h.selected || h.screen)
            return bad("waiting_nonzero");
        out = h; return Result::waiting;
    }
    if (!h.width || h.width > 1920 || !h.height || h.height > 1080 || h.pitch != h.width*4 || h.bytes != h.pitch*h.height)
        return bad("frame_dimensions");
    if (have_frame_ && (h.width != width_ || h.height != height_)) return bad("frame_size_changed");
    if (!h.sequence || h.sequence < sequence_) return bad("frame_sequence");
    if (have_frame_ && h.sequence == sequence_) { out = h; return Result::unchanged; }
    if (!h.capture_utc_ms || (h.capture_utc_ms > utc && h.capture_utc_ms-utc > 250) ||
        (h.capture_utc_ms <= utc && utc-h.capture_utc_ms > 1000)) return bad("frame_capture_age");
    sequence_ = h.sequence; observed_ = steady; width_ = h.width; height_ = h.height; have_frame_ = true;
    out = h; return Result::frame;
}
} // namespace minecome::hud::stream
