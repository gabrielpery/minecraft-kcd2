#include "hud_contract.hpp"
#include <algorithm>
#include <charconv>
#include <limits>
#include <map>

namespace minecome::hud {
namespace {
bool hex(std::string_view s, std::size_t n) {
    return s.size() == n && std::all_of(s.begin(), s.end(), [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}
bool number(std::string_view s, std::uint64_t &n) {
    if (s.empty() || s.size() > 20 || s.front() == '0') return false;
    if (!std::all_of(s.begin(), s.end(), [](char c) { return c >= '0' && c <= '9'; })) return false;
    const auto result = std::from_chars(s.data(), s.data() + s.size(), n);
    return result.ec == std::errc{} && result.ptr == s.data() + s.size() && n != 0;
}
bool local_raw_path(std::string_view p) {
    // Local drive-root paths only: no UNC, device namespace, ADS or relative IO.
    if (p.size() < 9 || p.size() > 2048 ||
        !((p[0] >= 'A' && p[0] <= 'Z') || (p[0] >= 'a' && p[0] <= 'z')) ||
        p[1] != ':' || (p[2] != '\\' && p[2] != '/')) return false;
    if (p.substr(p.size() - 5) != ".rgba") return false;
    for (std::size_t i = 2; i < p.size(); ++i)
        if (static_cast<unsigned char>(p[i]) < 32 || p[i] == ':' || p[i] == '"' ||
            p[i] == '*' || p[i] == '?' || p[i] == '<' || p[i] == '>' || p[i] == '|') return false;
    std::size_t pos = 3;
    while (pos < p.size()) {
        const auto end = p.find_first_of("/\\", pos);
        const auto part = p.substr(pos, end == p.npos ? p.size() - pos : end - pos);
        if (part.empty() || part == "." || part == ".." || part.back() == ' ' || part.back() == '.') return false;
        if (end == p.npos) break;
        pos = end + 1;
    }
    return true;
}
}
bool parse_arm(std::string_view text, std::uint32_t pid, std::uint64_t start,
               std::uint64_t now, Arm &out, std::string &error) {
    auto fail = [&](const char *reason) { error = reason; return false; };
    if (text.empty() || text.size() > max_config_bytes || text.find('\0') != text.npos)
        return fail("config_size_or_nul");
    if (text.starts_with("\xef\xbb\xbf")) text.remove_prefix(3);
    std::map<std::string, std::string, std::less<>> fields;
    bool section = false;
    std::size_t offset = 0, lines = 0;
    while (offset < text.size()) {
        const auto eol = text.find('\n', offset);
        auto line = text.substr(offset, eol == text.npos ? text.size() - offset : eol - offset);
        offset = eol == text.npos ? text.size() : eol + 1;
        if (++lines > 32 || line.size() > 4096) return fail("config_line_bound");
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty()) continue;
        if (!section) {
            if (line != "[HudPreview]") return fail("config_section");
            section = true; continue;
        }
        const auto eq = line.find('=');
        if (eq == line.npos || eq == 0 || eq + 1 == line.size()) return fail("config_field");
        std::string key(line.substr(0, eq)), value(line.substr(eq + 1));
        if (!fields.emplace(std::move(key), std::move(value)).second) return fail("config_duplicate");
    }
    if (!section) return fail("config_section");
    const auto get = [&](std::string_view key) -> std::string_view {
        const auto it = fields.find(key); return it == fields.end() ? std::string_view{} : it->second;
    };
    if (get("Schema") != "1" || !hex(get("Run"), 32)) return fail("schema_or_run");
    Arm parsed;
    parsed.run = get("Run");
    std::uint64_t p = 0, s = 0, expiry = 0, count = 0, w = 0, h = 0;
    if (!number(get("TargetPid"), p) || p > UINT32_MAX || p != pid ||
        !number(get("TargetStart"), s) || s != start) return fail("process_identity");
    if (!number(get("ExpiresUtcMs"), expiry) || expiry <= now || expiry - now > max_lease_ms)
        return fail("lease_bound");
    if (!number(get("FrameCount"), count) || count > 3 || !number(get("Width"), w) || w > 1920 ||
        !number(get("Height"), h) || h > 1080) return fail("frame_bound");
    if (fields.size() != 8 + 2 * count) return fail("config_unknown_or_missing");
    parsed.target_pid = static_cast<std::uint32_t>(p); parsed.target_start = s;
    parsed.expires_utc_ms = expiry; parsed.frame_count = static_cast<std::uint32_t>(count);
    parsed.width = static_cast<std::uint32_t>(w); parsed.height = static_cast<std::uint32_t>(h);
    for (std::uint32_t i = 0; i < count; ++i) {
        const auto suffix = std::to_string(i + 1);
        const auto path = get("Frame" + suffix), hash = get("Sha256_" + suffix);
        if (!local_raw_path(path) || !hex(hash, 64)) return fail("frame_path_or_hash");
        parsed.frames[i] = {std::string(path), std::string(hash)};
    }
    out = std::move(parsed); error.clear(); return true;
}
std::size_t byte_count(std::uint32_t w, std::uint32_t h) noexcept {
    return w && w <= 1920 && h && h <= 1080 ? static_cast<std::size_t>(w) * h * 4 : 0;
}
bool premultiply_rgba(std::span<std::uint8_t> pixels, std::uint32_t w, std::uint32_t h) noexcept {
    if (!byte_count(w, h) || pixels.size() != byte_count(w, h)) return false;
    for (std::size_t i = 0; i < pixels.size(); i += 4)
        for (std::size_t c = 0; c < 3; ++c)
            pixels[i + c] = static_cast<std::uint8_t>((static_cast<unsigned>(pixels[i + c]) * pixels[i + 3] + 127) / 255);
    return true;
}
Rect fit_rect(std::uint32_t sw, std::uint32_t sh, std::uint32_t tw, std::uint32_t th) noexcept {
    if (!byte_count(sw, sh) || !tw || !th || tw > 16384 || th > 16384) return {};
    const double scale = std::min(static_cast<double>(tw) / sw, static_cast<double>(th) / sh);
    const double w = sw * scale / tw, h = sh * scale / th;
    return {static_cast<float>((1 - w) / 2), static_cast<float>((1 - h) / 2),
            static_cast<float>(w), static_cast<float>(h)};
}
TeardownPlan teardown_plan(TeardownMode mode, bool cached_effect, bool bound, bool owned_resources) noexcept {
    const bool reset = mode == TeardownMode::after_runtime_reset;
    return {reset, !reset && cached_effect, bound || owned_resources, owned_resources};
}
bool Lease::accept(const Arm &arm, std::uint64_t utc, std::uint64_t steady) noexcept {
    if (consumed_ || arm.expires_utc_ms <= utc || arm.expires_utc_ms - utc > max_lease_ms ||
        arm.frame_count < 1 || arm.frame_count > 3 || steady > UINT64_MAX - max_lease_ms) return false;
    consumed_ = true; start_steady_ = steady; expires_utc_ = arm.expires_utc_ms;
    deadline_steady_ = steady + std::min(max_lease_ms, arm.expires_utc_ms - utc);
    count_ = arm.frame_count; return true;
}
bool Lease::live(std::uint64_t utc, std::uint64_t steady) const noexcept {
    return consumed_ && utc < expires_utc_ && steady >= start_steady_ && steady < deadline_steady_;
}
std::uint32_t Lease::frame_index(std::uint64_t steady) const noexcept {
    return consumed_ && count_ && steady >= start_steady_ ?
        static_cast<std::uint32_t>(((steady - start_steady_) / 3000) % count_) : 0;
}
} // namespace minecome::hud
