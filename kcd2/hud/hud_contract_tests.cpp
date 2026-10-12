#include "hud_contract.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
namespace hud = minecome::hud;
namespace {
unsigned checks = 0;
void check(bool value, const char *why) { ++checks; if (!value) throw std::runtime_error(why); }
bool near(float a, float b) { return std::abs(a - b) < .00001f; }
const std::string hash(64, 'a');
std::string config(unsigned count = 3) {
    std::string s = "[HudPreview]\nSchema=1\nRun=0123456789abcdef0123456789abcdef\nTargetPid=42\n"
        "TargetStart=18446744073709551615\nExpiresUtcMs=145000\nFrameCount=" + std::to_string(count) +
        "\nWidth=1920\nHeight=1080\n";
    for (unsigned i = 1; i <= count; ++i) s += "Frame" + std::to_string(i) + "=C:\\proof\\hud-000" +
        std::to_string(i) + ".rgba\nSha256_" + std::to_string(i) + "=" + hash + "\n";
    return s;
}
bool parse(const std::string &s, hud::Arm &out, std::uint64_t now = 100000) {
    std::string error; return hud::parse_arm(s, 42, UINT64_MAX, now, out, error);
}
std::string replace(std::string s, std::string_view from, std::string_view to) {
    const auto pos = s.find(from); if (pos == s.npos) throw std::runtime_error("fixture replacement");
    s.replace(pos, from.size(), to); return s;
}
}
int main() {
    try {
        hud::Arm arm;
        check(parse(config(), arm), "valid bounded exact u64 arm");
        check(arm.target_start == UINT64_MAX && arm.width == 1920 && arm.frames[2].path.ends_with("0003.rgba"), "parsed identity/frames");
        for (unsigned count = 1; count <= 3; ++count) check(parse(config(count), arm) && arm.frame_count == count, "1..3 frames");
        check(parse("\xef\xbb\xbf" + config(), arm), "UTF8 BOM accepted");
        auto crlf = config(); std::size_t pos = 0;
        while ((pos = crlf.find('\n', pos)) != crlf.npos) { crlf.insert(pos, "\r"); pos += 2; }
        check(parse(crlf, arm), "CRLF arm");
        check(parse(replace(config(), "C:\\proof\\hud-0001", "C:\\proof with space\\hud-0001"), arm), "space path");
        const std::vector<std::pair<std::string, std::string>> bad = {
            {"[HudPreview]", "[Other]"}, {"Schema=1", "Schema=2"}, {"TargetPid=42", "TargetPid=43"},
            {"TargetPid=42", "TargetPid=042"}, {"TargetPid=42", "TargetPid=+42"},
            {"TargetPid=42", "TargetPid=4294967296"}, {"TargetPid=42", "TargetPid=4.2e1"},
            {"TargetStart=18446744073709551615", "TargetStart=18446744073709551616"},
            {"TargetStart=18446744073709551615", "TargetStart=18446744073709551614"},
            {"ExpiresUtcMs=145000", "ExpiresUtcMs=145001"}, {"ExpiresUtcMs=145000", "ExpiresUtcMs=100000"},
            {"FrameCount=3", "FrameCount=4"}, {"Width=1920", "Width=1921"}, {"Width=1920", "Width=0"},
            {"Height=1080", "Height=1081"}, {"Height=1080", "Height=-1"},
            {"Run=0123456789abcdef0123456789abcdef", "Run=0123456789ABCDEF0123456789abcdef"},
            {"Frame1=C:\\proof\\hud-0001.rgba", "Frame1=relative.rgba"},
            {"Frame1=C:\\proof\\hud-0001.rgba", "Frame1=\\\\server\\proof\\hud-0001.rgba"},
            {"Frame1=C:\\proof\\hud-0001.rgba", "Frame1=C:\\proof\\..\\hud-0001.rgba"},
            {"Frame1=C:\\proof\\hud-0001.rgba", "Frame1=C:\\proof\\hud-0001.rgba:stream"},
            {"Frame1=C:\\proof\\hud-0001.rgba", "Frame1=C:\\proof\\hud-0001.png"},
            {"Sha256_1=" + hash, "Sha256_1=" + std::string(64, 'g')}
        };
        for (const auto &[from, to] : bad) {
            arm.run = "unchanged";
            check(!parse(replace(config(), from, to), arm), "invalid arm rejected");
            check(arm.run == "unchanged", "invalid parse transactional");
        }
        check(!parse(config() + "Schema=1\n", arm), "duplicate key");
        check(!parse(config() + "Unknown=1\n", arm), "unknown key");
        check(!parse(config() + "[HudPreview]\n", arm), "duplicate section");
        check(!parse(config() + std::string(4097, 'x'), arm), "overlong line");
        check(!parse(config() + std::string(32768, 'x'), arm), "overlong document");
        check(!parse(config() + std::string(1, '\0'), arm), "NUL");
        check(!parse(replace(config(), "Sha256_3=" + hash + "\n", ""), arm), "missing frame hash");
        check(!parse(config(3), arm, 145000), "expired arm");
        check(hud::byte_count(1920,1080) == 8294400, "exact bounded bytes");
        check(hud::byte_count(UINT32_MAX,UINT32_MAX) == 0 && hud::byte_count(1,0) == 0, "size overflow prevented");
        std::vector<std::uint8_t> pixels{255,50,100,0, 255,127,1,128, 80,90,100,255, 3,5,7,64};
        check(hud::premultiply_rgba(pixels,2,2), "premultiply exact canvas");
        const std::vector<std::uint8_t> expected{0,0,0,0, 128,64,1,128, 80,90,100,255, 1,1,2,64};
        check(pixels == expected, "top-left order, transparent/partial/opaque, alpha retained");
        check(!hud::premultiply_rgba(pixels,2,3), "wrong raw byte length rejected");
        check(pixels == expected, "failed premultiply leaves pixels unchanged");
        for (unsigned a : {0u,1u,64u,127u,128u,254u,255u}) {
            std::vector<std::uint8_t> pixel{200,100,50,static_cast<std::uint8_t>(a)};
            check(hud::premultiply_rgba(pixel,1,1), "alpha fixture");
            // ONE/INV_SRC_ALPHA over black: premult channel, not alpha squared.
            check(std::abs(static_cast<int>(pixel[0]) - static_cast<int>(std::lround(200.0 * a / 255))) <= 1, "single alpha blend");
        }
        auto rect = hud::fit_rect(1920,1080,1920,1080);
        check(near(rect.x,0) && near(rect.y,0) && near(rect.width,1) && near(rect.height,1), "full canvas");
        rect = hud::fit_rect(640,360,1920,1080);
        check(near(rect.width,1) && near(rect.height,1), "integer 3x scale");
        rect = hud::fit_rect(640,360,1600,900);
        check(near(rect.x,0) && near(rect.y,0) && near(rect.width,1) && near(rect.height,1), "noninteger same-aspect scale fills target");
        // Actual first live preview: flooring 2.9976x to 2x incorrectly made
        // the entire vanilla UI appear inside a centered 1708x960 canvas.
        rect = hud::fit_rect(854,480,2560,1440);
        check(near(rect.x,0) && near(rect.width,1) && near(rect.y,1.0f/2562) &&
            near(rect.height,1280.0f/1281), "live 854x480 canvas fills 2560x1440 width with only aspect-ratio letterbox");
        rect = hud::fit_rect(640,480,1920,1080);
        check(near(rect.x,.125f) && near(rect.y,0) && near(rect.width,.75f) && near(rect.height,1), "4:3 canvas pillarboxed inside 16:9 without stretching");
        rect = hud::fit_rect(1920,1080,1280,720);
        check(near(rect.width,1) && near(rect.height,1), "aspect-preserving shrink");
        rect = hud::fit_rect(1920,1080,1280,1024);
        check(near(rect.y,.1484375f) && near(rect.height,.703125f), "resize pillar/letterbox");
        check(hud::fit_rect(1920,1080,0,1080).width == 0, "zero target hidden");
        check(hud::fit_rect(1920,1080,UINT32_MAX,1080).width == 0, "unbounded target hidden");
        check(hud::fit_rect(1920,1080,1920,0).height == 0 &&
            hud::fit_rect(1920,1080,1920,16385).height == 0, "zero or unbounded target height hidden");
        check(hud::fit_rect(0,480,2560,1440).width == 0 &&
            hud::fit_rect(1921,1080,2560,1440).width == 0 &&
            hud::fit_rect(1920,1081,2560,1440).height == 0, "invalid source dimensions hidden");
        for (const auto [tw, th] : {std::pair{1u,1u}, {1600u,900u}, {2560u,1440u}, {16384u,1u}, {1u,16384u}}) {
            const auto fitted = hud::fit_rect(854,480,tw,th);
            check(std::isfinite(fitted.x) && std::isfinite(fitted.y) &&
                fitted.x >= 0 && fitted.y >= 0 && fitted.width > 0 && fitted.height > 0 &&
                fitted.x + fitted.width <= 1.00001f && fitted.y + fitted.height <= 1.00001f,
                "valid extreme and ordinary targets remain inside normalized canvas");
            check(near(fitted.width,1) || near(fitted.height,1), "aspect-fit fills at least one target axis");
        }
        // Reproduce the actual SDK ordering: an FX handle is cached, then its
        // object is destroyed before the addon receives runtime reset. The
        // lifecycle harness poisons that handle and rejects any uniform use.
        struct Lifetime {
            bool effects_alive = true, cached_effect = true, semantic_bound = true;
            bool own_view = true, own_texture = true, game_texture = true;
            unsigned hides = 0, invalidations = 0, cache_erases = 0, waits = 0;
            void apply(hud::TeardownMode mode) {
                const auto plan = hud::teardown_plan(mode, cached_effect, semantic_bound, own_texture);
                if (plan.invalidate_effect_handles) { cached_effect = false; ++invalidations; }
                if (plan.hide_effect) {
                    if (!effects_alive || !cached_effect) throw std::runtime_error("poisoned FX handle dereference");
                    ++hides;
                }
                if (plan.erase_semantic_cache) { semantic_bound = false; ++cache_erases; }
                if (plan.destroy_owned_resources) { ++waits; own_view = false; own_texture = false; }
            }
        };
        Lifetime reset;
        reset.effects_alive = false; // SDK destroy_effects precedes callback.
        reset.apply(hud::TeardownMode::after_runtime_reset);
        check(!reset.cached_effect && reset.invalidations == 1 && reset.hides == 0, "destroy callback cannot use poisoned FX handle");
        check(!reset.semantic_bound && reset.cache_erases == 1, "persistent semantic cache retired despite destroyed effects");
        check(reset.waits == 1 && !reset.own_view && !reset.own_texture && reset.game_texture, "owned-only reset cleanup after GPU idle");
        reset.apply(hud::TeardownMode::after_runtime_reset);
        check(reset.hides == 0 && reset.waits == 1 && reset.cache_erases == 1, "repeated reset does not destroy assets twice");
        reset.effects_alive = true; // Reinitialize runtime on same window.
        check(!reset.cached_effect && !reset.semantic_bound, "resize reinitialization retains no destroyed handles/views");
        Lifetime live;
        live.apply(hud::TeardownMode::live_effects);
        check(live.hides == 1 && live.invalidations == 0 && live.waits == 1 && live.game_texture, "live expiry hides effect before owned cleanup");
        Lifetime disarmed;
        disarmed.cached_effect = false; disarmed.semantic_bound = false;
        disarmed.own_view = false; disarmed.own_texture = false; disarmed.effects_alive = false;
        disarmed.apply(hud::TeardownMode::after_runtime_reset);
        check(disarmed.hides == 0 && disarmed.waits == 0 && disarmed.cache_erases == 0, "disarmed reset has no shader or GPU operations");
        for (bool cached : {false, true}) for (bool bound : {false, true}) for (bool owned : {false, true}) {
            const auto plan = hud::teardown_plan(hud::TeardownMode::after_runtime_reset, cached, bound, owned);
            check(plan.invalidate_effect_handles && !plan.hide_effect &&
                plan.erase_semantic_cache == (bound || owned) && plan.destroy_owned_resources == owned,
                "reset policy safe across cached/binding/owned combinations");
        }
        check(parse(config(), arm), "lease fixture");
        hud::Lease lease;
        check(!lease.live(100000,1000), "unarmed inactive");
        check(lease.accept(arm,100000,1000), "first arm");
        check(lease.live(100000,1000) && lease.frame_index(1000) == 0, "first snapshot");
        check(lease.frame_index(3999) == 0 && lease.frame_index(4000) == 1 && lease.frame_index(7000) == 2 && lease.frame_index(10000) == 0, "3s cycle");
        check(!lease.accept(arm,100100,1100), "same run cannot renew");
        arm.run = std::string(32,'b'); arm.expires_utc_ms = 145100;
        check(!lease.accept(arm,100100,1100), "new run cannot renew");
        // A renderer reload/resize does not own or reset this lease.
        check(lease.live(144999,45999) && !lease.live(144999,46000), "steady fixed deadline");
        check(!lease.live(145000,2000), "UTC deadline hides after clock jump");
        check(!lease.live(90000,46000), "UTC rewind cannot extend steady lease");
        check(!lease.live(100001,999), "steady rewind rejected");
        hud::Lease short_lease;
        arm.expires_utc_ms = 100500;
        check(short_lease.accept(arm,100000,5000) && !short_lease.live(100499,5500), "short UTC remaining bounds steady lease");
        hud::Lease overflow;
        check(!overflow.accept(arm,100000,UINT64_MAX), "steady overflow rejected");
        std::cout << "HUD static contract: " << checks << " checks passed; standalone only, no GPU/game/visual proof\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << "HUD contract failed: " << e.what() << '\n'; return 1; }
}
