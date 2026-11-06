#include "stream_contract.hpp"
#include <algorithm>
#include <bit>
#include <charconv>
#include <cmath>
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
float f32(std::span<const std::uint8_t> h, std::size_t at) { return std::bit_cast<float>(u32(h,at)); }
float dot(const std::array<float,3> &a,const std::array<float,3> &b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
bool finite(const std::array<float,3> &a) { return std::all_of(a.begin(),a.end(),[](float x){return std::isfinite(x);}); }
}
bool valid_identity(const Identity &id) noexcept {
    return token(id.run) && id.producer_pid && id.target_pid && id.producer_start &&
        id.target_start && id.expires_utc_ms && (id.schema == 1 || id.schema == 3);
}
bool parse_arm(std::string_view text, std::uint32_t target_pid, std::uint64_t target_start,
               std::uint64_t utc, Identity &out, std::string &error, std::uint32_t expected_schema) {
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
    if (!section || fields.size() != 7 || (expected_schema != 1 && expected_schema != 3) ||
        fields["Schema"] != std::to_string(expected_schema)) return fail("config_schema_or_missing");
    Identity id; id.run = fields["Run"]; id.schema = expected_schema;
    if (!number(fields["TargetPid"], id.target_pid) || !number(fields["ProducerPid"], id.producer_pid) ||
        !number(fields["TargetStart"], id.target_start) || !number(fields["ProducerStart"], id.producer_start) ||
        !number(fields["ExpiresUtcMs"], id.expires_utc_ms) || !valid_identity(id)) return fail("config_identity");
    if (id.target_pid != target_pid || id.target_start != target_start) return fail("config_target");
    if (id.expires_utc_ms <= utc || id.expires_utc_ms-utc > maximum_lease(id)) return fail("config_expiry");
    out = std::move(id); return true;
}
bool Validator::start(const Identity &id, std::uint64_t utc, std::uint64_t steady) {
    if (consumed_) return false;
    consumed_ = true;
    if (!valid_identity(id) || id.expires_utc_ms <= utc || id.expires_utc_ms-utc > maximum_lease(id) ||
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
    const std::string_view magic = identity_.schema == 3 ? "MCHUDS03" : "MCHUDS01";
    if (!std::equal(magic.begin(), magic.end(), bytes.begin()) || u32(bytes,8) != identity_.schema || u32(bytes,12) != header_bytes)
        return bad("header_magic_or_schema");
    if (!std::equal(identity_.run.begin(), identity_.run.end(), bytes.begin()+16) ||
        u32(bytes,48) != identity_.producer_pid || u32(bytes,52) != identity_.target_pid ||
        u64(bytes,56) != identity_.producer_start || u64(bytes,64) != identity_.target_start ||
        u64(bytes,72) != identity_.expires_utc_ms) return bad("header_identity");
    Header h; h.sequence = u64(bytes,80); h.capture_utc_ms = u64(bytes,88);
    h.width = u32(bytes,96); h.height = u32(bytes,100); h.pitch = u32(bytes,104); h.bytes = u32(bytes,108);
    h.format = u32(bytes,112); h.state = u32(bytes,116); h.selected = u32(bytes,120); h.screen = u32(bytes,124);
    if ((h.format != 1 && !(identity_.schema == 3 && h.format == 2)) || h.state > 2 || h.selected > 8 || h.screen > 1)
        return bad("header_format_or_state");
    if (format_ && format_ != h.format) return bad("frame_format_changed");
    const bool camera_present = h.format == 2 && h.state != 0 && h.sequence != 0;
    if (std::any_of(bytes.begin()+(camera_present?184:128),bytes.end(),[](auto b){return b!=0;})) return bad("header_reserved");
    if(camera_present) {
        h.camera_utc_ms=u64(bytes,128);
        for(unsigned i=0;i<3;++i){h.camera_position[i]=f32(bytes,136+i*4);h.camera_direction[i]=f32(bytes,148+i*4);h.camera_up[i]=f32(bytes,160+i*4);}
        h.vertical_fov=f32(bytes,172);h.near_plane=f32(bytes,176);h.far_plane=f32(bytes,180);
        if(!finite(h.camera_position)||!finite(h.camera_direction)||!finite(h.camera_up)||!std::isfinite(h.vertical_fov)||
            !std::isfinite(h.near_plane)||!std::isfinite(h.far_plane)||h.near_plane<=0.f||h.far_plane<=h.near_plane)
            return bad("frame_camera");
        const std::array<float,3> zero{};
        const bool no_world_camera=!h.camera_utc_ms&&h.camera_position==zero&&h.camera_direction==zero&&h.camera_up==zero&&h.vertical_fov==0.f;
        if(!no_world_camera&&(h.vertical_fov<=.05f||h.vertical_fov>=3.09159265f||
            std::abs(dot(h.camera_direction,h.camera_direction)-1.f)>.01f||
            std::abs(dot(h.camera_up,h.camera_up)-1.f)>.01f||std::abs(dot(h.camera_direction,h.camera_up))>.05f))
            return bad("frame_camera");
        if(h.camera_utc_ms && ((h.camera_utc_ms>h.capture_utc_ms && h.camera_utc_ms-h.capture_utc_ms>50) ||
            (h.camera_utc_ms<=h.capture_utc_ms && h.capture_utc_ms-h.camera_utc_ms>1000))) return bad("frame_camera_age");
    }
    const std::uint32_t planes = h.format == 2 ? 3u : 1u;
    const auto dimensions = [&] {
        return h.width && h.width <= 1920 && h.height && h.height <= 1080 &&
            h.pitch == h.width*4 && h.bytes == h.pitch*h.height*planes;
    };
    format_ = h.format;
    if (h.state == 2) {
        if (!h.sequence) {
            if (h.capture_utc_ms || h.width || h.height || h.pitch || h.bytes || h.selected || h.screen)
                return bad("closed_waiting_nonzero");
        } else if (!h.capture_utc_ms || !dimensions()) return bad("closed_frame_dimensions");
        invalidate("closed"); out = h; return Result::closed;
    }
    if (h.state == 0) {
        if (have_frame_) return bad("waiting_after_frame");
        if (h.sequence || h.capture_utc_ms || h.width || h.height || h.pitch || h.bytes || h.selected || h.screen)
            return bad("waiting_nonzero");
        out = h; return Result::waiting;
    }
    if (!dimensions()) return bad("frame_dimensions");
    if (have_frame_ && (h.width != width_ || h.height != height_)) return bad("frame_size_changed");
    if (!h.sequence || h.sequence < sequence_) return bad("frame_sequence");
    if (have_frame_ && h.sequence == sequence_) { out = h; return Result::unchanged; }
    if (!h.capture_utc_ms || (h.capture_utc_ms > utc && h.capture_utc_ms-utc > 250) ||
        (h.capture_utc_ms <= utc && utc-h.capture_utc_ms > 1000)) return bad("frame_capture_age");
    sequence_ = h.sequence; observed_ = steady; width_ = h.width; height_ = h.height; have_frame_ = true;
    out = h; return Result::frame;
}
} // namespace minecome::hud::stream
