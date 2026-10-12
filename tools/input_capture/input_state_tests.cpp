#include "input_state.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace ic = minecome::input_capture;
namespace {
unsigned checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
bool controls_neutral(const ic::Snapshot& sample) {
    return std::none_of(sample.held.begin(), sample.held.end(), [](bool b) { return b; }) &&
        sample.mouse_dx == 0 && sample.mouse_dy == 0;
}
void arm(ic::InputState& state) {
    state.f8(false);
    state.f8(true);
    const auto sample = state.sample();
    check(sample.focused && sample.armed && controls_neutral(sample), "F8 must produce neutral armed sample");
}
template<class Function> void throws(Function function, const char* message) {
    bool rejected{};
    try { function(); } catch (const std::invalid_argument&) { rejected = true; }
    check(rejected, message);
}

void focus_and_suppression() {
    ic::InputState state;
    state.control(ic::Control::forward, true);
    state.f8(true);
    state.relative_mouse(3, 4);
    auto sample = state.sample();
    check(!sample.focused && !sample.armed && controls_neutral(sample), "background input must be neutral");
    ic::ControlBits held{};
    held[0] = true;
    state.focus(true, held, true);
    state.f8(true);
    check(!state.sample().armed, "held F8 through focus must not arm");
    state.f8(false);
    state.f8(true);
    check(!state.sample().armed, "held W must prevent fresh F8 arm");
    state.control(ic::Control::forward, false);
    state.f8(true);
    check(!state.sample().armed, "F8 repeat after W release must not arm");
    arm(state);
    state.control(ic::Control::forward, true);
    state.relative_mouse(5, -7);
    sample = state.sample();
    check(sample.held[0] && sample.mouse_dx == 5 && sample.mouse_dy == -7, "fresh focused controls accepted");
    state.focus(false);
    sample = state.sample();
    check(!sample.focused && !sample.armed && controls_neutral(sample), "focus loss immediately neutralizes state");
    state.focus(true, held, false);
    state.control(ic::Control::forward, true);
    state.f8(true);
    check(!state.sample().armed, "held control across focus is suppressed");
    state.control(ic::Control::forward, false);
    arm(state);
    state.control(ic::Control::forward, true);
    check(state.sample().held[0], "released/repressed control after focus works");
}

void neutral_arm_and_menu() {
    ic::InputState state;
    state.focus(true);
    state.f8(true);
    state.control(ic::Control::jump, true);
    state.relative_mouse(42, 12);
    auto sample = state.sample();
    check(sample.armed && controls_neutral(sample), "first arm sample neutral even with early control");
    state.control(ic::Control::jump, true);
    check(!state.sample().held[4], "early held control stays suppressed after neutral sample");
    state.control(ic::Control::jump, false);
    state.control(ic::Control::jump, true);
    check(state.sample().held[4], "early control must be released/repressed");
    state.relative_mouse(9, -9);
    state.disarm(); // Esc, backtick, unsupported action, overrun or stale packet.
    sample = state.sample();
    check(sample.focused && !sample.armed && controls_neutral(sample), "menu/error latch clears controls and mouse");
    state.f8(true);
    check(!state.sample().armed, "held F8 cannot auto-rearm after menu");
    state.control(ic::Control::jump, false);
    arm(state);
    state.control(ic::Control::sprint, true);
    state.control(ic::Control::sprint, true);
    check(state.sample().held[5], "mapped typematic keeps accepted state");
    state.control(ic::Control::sprint, false);
    check(!state.sample().held[5], "mapped BREAK releases state");
    state.focus(false); // Device change resets through focus baseline.
    state.focus(true, {}, true);
    state.f8(true);
    check(!state.sample().armed, "device reset cannot rearm from F8 repeat");
}

void async_baseline_and_mouse_bounds() {
    ic::InputState state;
    state.focus(true);
    ic::ControlBits held{};
    held[3] = true;
    state.suppress_currently_down(held);
    state.f8(true);
    check(!state.sample().armed, "fresh asynchronous high-bit held control prevents arm");
    state.control(ic::Control::right, false);
    arm(state);
    state.relative_mouse(std::numeric_limits<std::int32_t>::max(), std::numeric_limits<std::int32_t>::min());
    auto sample = state.sample();
    check(sample.mouse_dx == 32767 && sample.mouse_dy == -32767, "mouse accumulation clamps without overflow");
    check(controls_neutral(state.sample()), "mouse consumed once per sample");
    state.relative_mouse(32000, -32000);
    state.relative_mouse(32000, -32000);
    sample = state.sample();
    check(sample.mouse_dx == 32767 && sample.mouse_dy == -32767, "repeated deltas bounded");
    state.relative_mouse(10, 20);
    state.disarm();
    state.relative_mouse(90, 90);
    check(controls_neutral(state.sample()), "disarm drops pending and future deltas");
}

void queued_packet_epoch() {
    check(ic::packet_is_fresh(150, 200, 100), "fresh current epoch packet accepted");
    check(!ic::packet_is_fresh(99, 200, 100), "packet older than 100ms rejected");
    check(!ic::packet_is_fresh(149, 200, 150), "packet from before arm epoch rejected");
    check(!ic::packet_is_fresh(150, 200, 150), "same millisecond epoch is ambiguous and rejected");
    check(ic::packet_is_fresh(151, 200, 150), "strictly later epoch accepted");
    check(!ic::packet_is_fresh(201, 200, 100), "future queued timestamp rejected");
    check(ic::packet_is_fresh(0xfffffff0U, 0x20U, 0xffffffe0U), "DWORD wrap fresh interval accepted");
    check(!ic::packet_is_fresh(0xffffffd0U, 0x20U, 0xffffffe0U), "DWORD wrap previous epoch rejected");
    check(!ic::packet_is_fresh(0xffffff00U, 0x20U, 0xffffffe0U), "DWORD wrap stale packet rejected");
    check(ic::classify_packet(150, 200, 150) == ic::PacketDisposition::previous_epoch, "epoch equality classified separately from stale");
    check(ic::classify_packet(1, 200, 150) == ic::PacketDisposition::stale, "missed-release stale backlog classified as reset");
}

void coarse_tick_liveness() {
    ic::InputState state;
    state.focus(true);
    arm(state);
    std::uint32_t epoch = 100;
    for (std::uint32_t now = 100; now <= 115; ++now) {
        for (unsigned i = 0; i < 32; ++i) {
            const auto disposition = ic::classify_packet(100, now, epoch);
            check(disposition == ic::PacketDisposition::previous_epoch, "same coarse-tick flood drops old phase only");
            // Matches platform's suppression-only action, with released controls.
            state.suppress_currently_down({});
            state.suppress_f8_until_release(true);
        }
    }
    check(epoch == 100 && state.armed(), "old phase flood must not renew epoch or disarm");
    check(ic::classify_packet(116, 116, epoch) == ic::PacketDisposition::accept, "new coarse-tick packets become live");
    state.relative_mouse(3, 4);
    auto sample = state.sample();
    check(sample.armed && sample.mouse_dx == 3 && sample.mouse_dy == 4, "mouse resumes after old epoch backlog");
    state.disarm();
    state.f8(true);
    check(!state.sample().armed, "filtered F8 MAKE must not autoarm via repeat");
    arm(state);
    check(state.armed(), "release and fresh press rearm after filtered MAKE");
    state.control(ic::Control::forward, true);
    check(state.sample().held[0], "fresh controls remain live after recovery");
}

void strict_record_contract() {
    std::uint64_t parsed{};
    check(ic::canonical_positive_decimal("18446744073709551615", parsed) && parsed == UINT64_MAX, "u64 FILETIME stays exact");
    for (auto text : {"", "0", "00", "01", "+1", "-1", "1.0", " 1", "1 ", "18446744073709551616"})
        check(!ic::canonical_positive_decimal(text, parsed), "invalid canonical positive decimal rejected");
    check(ic::valid_run("0123456789abcdef0123456789abcdef"), "lowerhex run accepted");
    check(!ic::valid_run("0123456789ABCDEF0123456789abcdef") && !ic::valid_run("abc"), "uppercase/short run rejected");
    const ic::RecordIdentity identity{"0123456789abcdef0123456789abcdef", 123, "134046111222333444"};
    const auto begin = ic::record_json(identity, "begin", 1, 1000, 0, {});
    check(begin.find("\"source_kind\":\"windows_raw_input_v1\"") != std::string::npos, "source contract exact");
    check(begin.find("\"target_start_filetime\":\"134046111222333444\"") != std::string::npos, "FILETIME serialized as decimal string");
    check(begin.find("\"reason\"") == std::string::npos && begin.back() == '\n', "begin exact fields/no reason NDJSON");
    const auto end = ic::record_json(identity, "end", 3, 1100, 100, {}, "duration");
    check(end.find("\"reason\":\"duration\"") != std::string::npos, "terminal reason present");
    ic::Snapshot active{true, true, {}, 3, -4};
    active.held[2] = true;
    const auto sample = ic::record_json(identity, "sample", 2, 1050, 50, active);
    check(sample.find("\"left\":true") != std::string::npos && sample.find("\"mouse_dx\":3") != std::string::npos, "held/deltas emitted");
    throws([&] { ic::record_json(identity, "begin", 1, 1000, 0, active); }, "begin must be neutral");
    throws([&] { ic::record_json(identity, "end", 3, 1100, 100, active, "duration"); }, "end must be neutral");
    active.focused = false;
    throws([&] { ic::record_json(identity, "sample", 2, 1050, 50, active); }, "inactive cannot carry controls");
    active = {true, false, {}, 1, 0};
    throws([&] { ic::record_json(identity, "sample", 2, 1050, 50, active); }, "disarmed cannot carry deltas");
    active = {true, true, {}, 32768, 0};
    throws([&] { ic::record_json(identity, "sample", 2, 1050, 50, active); }, "out of bound delta rejected");
    throws([&] { ic::record_json(identity, "end", 3, 1100, 100, {}, "fake"); }, "unknown terminal reason rejected");
    throws([&] { ic::record_json(identity, "sample", 2, 1050, 50, {}, "duration"); }, "sample extra reason rejected");
    throws([&] { ic::record_json(identity, "begin", 1, 1000, 1, {}); }, "begin elapsed must be zero");
    throws([&] { ic::record_json(identity, "begin", 2, 1000, 0, {}); }, "begin sequence must be one");
    throws([&] { ic::record_json(identity, "sample", 0, 1000, 1, {}); }, "zero sequence rejected");
}

void registration_flag_readback() {
    check(ic::valid_registration_flags(0x100), "measured INPUTSINK-only OS readback accepted");
    check(ic::valid_registration_flags(0x2100), "INPUTSINK plus requested DEVNOTIFY readback accepted");
    for (const std::uint32_t flags : {0U, 0x2000U, 0x130U, 0x2130U, 0x300U, 0x2300U,
                                    0x1100U, 0x3100U, 0x1000U, 0x101U, 0x1000100U, 0xffffffffU})
        check(!ic::valid_registration_flags(flags), "suppression/alternate/unknown readback flag rejected");
}

void bounded_arm_window() {
    ic::CaptureWindow immediate(30, 0);
    check(!immediate.waiting() && !immediate.expired(29999) && immediate.expired(30000), "legacy capture duration unchanged");
    check(!immediate.observe_arm(25000, true) && immediate.expired(30000), "legacy arm cannot extend duration");
    ic::CaptureWindow waiting(30, 60);
    check(waiting.waiting() && !waiting.expired(59999), "operator gets full bounded wait");
    check(!waiting.observe_arm(20000, false) && waiting.waiting(), "neutral samples never start active timer");
    check(waiting.observe_arm(59999, true) && !waiting.waiting(), "last in-window arm starts active duration");
    check(!waiting.expired(89998) && waiting.expired(89999), "active duration ends relative to first arm");
    check(!waiting.observe_arm(70000, false) && !waiting.observe_arm(80000, true) && waiting.expired(89999), "focus loss and rearm never renew deadline");
    ic::CaptureWindow timeout(40, 60);
    check(timeout.expired(60000) && !timeout.observe_arm(60000, true) && timeout.waiting(), "arm at deadline cannot revive timed-out capture");
    check(!timeout.observe_arm(70000, true), "late arm remains rejected");
    ic::CaptureWindow early(40, 60);
    check(early.observe_arm(50, true) && early.expired(40050), "early arm removes unused waiting allowance");
    ic::CaptureWindow longest(60, 60);
    check(longest.observe_arm(59999, true) && longest.expired(119999), "maximum permitted total stays below protocol120s");
    throws([] { ic::CaptureWindow bad(14, 60); }, "too-short duration rejected");
    throws([] { ic::CaptureWindow bad(121, 0); }, "too-long duration rejected");
    throws([] { ic::CaptureWindow bad(30, 61); }, "overlong wait rejected");
    throws([] { ic::CaptureWindow bad(61, 60); }, "combined interval beyond protocol bound rejected");
}
} // namespace

int main() {
    try {
        focus_and_suppression();
        neutral_arm_and_menu();
        async_baseline_and_mouse_bounds();
        queued_packet_epoch();
        coarse_tick_liveness();
        strict_record_contract();
        registration_flag_readback();
        bounded_arm_window();
        std::cout << "INPUT_CAPTURE_TESTS_PASS checks=" << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "INPUT_CAPTURE_TESTS_FAIL " << error.what() << '\n';
        return 1;
    }
}
