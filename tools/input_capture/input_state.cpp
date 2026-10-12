#include "input_state.hpp"

#include <algorithm>
#include <charconv>
#include <stdexcept>

namespace minecome::input_capture {

CaptureWindow::CaptureWindow(unsigned seconds, unsigned arm_wait_seconds)
    : duration_ms_(static_cast<std::uint64_t>(seconds) * 1000),
      deadline_ms_(arm_wait_seconds ? static_cast<std::uint64_t>(arm_wait_seconds) * 1000 : duration_ms_),
      waiting_(arm_wait_seconds != 0) {
    if (seconds < 15 || seconds > 120 || arm_wait_seconds > 60 || seconds + arm_wait_seconds > 120)
        throw std::invalid_argument("capture duration plus arm wait must fit120s; duration15..120s, wait0..60s");
}

bool CaptureWindow::observe_arm(std::uint64_t elapsed_ms, bool armed) {
    if (!waiting_ || !armed || expired(elapsed_ms)) return false;
    waiting_ = false;
    deadline_ms_ = elapsed_ms + duration_ms_;
    return true;
}

void InputState::focus(bool focused, ControlBits currently_down, bool f8_down) {
    if (focused == focused_) return;
    focused_ = focused;
    armed_ = false;
    awaiting_neutral_ = false;
    held_ = {};
    dx_ = dy_ = 0;
    physical_ = focused ? currently_down : ControlBits{};
    suppressed_ = physical_;
    f8_down_ = focused && f8_down;
}

void InputState::control(Control key, bool down) {
    const auto index = static_cast<unsigned>(key);
    if (!focused_ || index >= control_count) return;
    const bool edge = down && !physical_[index];
    physical_[index] = down;
    if (!down) {
        suppressed_[index] = false;
        held_[index] = false;
    } else if (!armed_ || awaiting_neutral_) {
        suppressed_[index] = true;
    } else if (edge && !suppressed_[index]) {
        held_[index] = true;
    }
}

void InputState::f8(bool down) {
    if (!focused_) return;
    const bool edge = down && !f8_down_;
    f8_down_ = down;
    if (!edge || armed_) return;
    if (std::any_of(physical_.begin(), physical_.end(), [](bool b) { return b; })) return;
    armed_ = true;
    awaiting_neutral_ = true;
    held_ = {};
    dx_ = dy_ = 0;
}

void InputState::disarm() {
    armed_ = false;
    awaiting_neutral_ = false;
    suppressed_ = physical_;
    held_ = {};
    dx_ = dy_ = 0;
    // f8_down_ is retained: typematic cannot re-arm after a menu/error.
}

void InputState::suppress_currently_down(ControlBits currently_down) {
    if (!focused_) return;
    for (unsigned i = 0; i < control_count; ++i) {
        if (currently_down[i]) {
            physical_[i] = true;
            suppressed_[i] = true;
            held_[i] = false;
        }
    }
}

void InputState::suppress_f8_until_release(bool currently_down) {
    if (focused_ && currently_down) f8_down_ = true;
}

void InputState::relative_mouse(std::int32_t dx, std::int32_t dy) {
    if (!focused_ || !armed_ || awaiting_neutral_) return;
    auto add = [](std::int32_t current, std::int32_t delta) {
        return static_cast<std::int32_t>(std::clamp<std::int64_t>(
            static_cast<std::int64_t>(current) + delta, -32767, 32767));
    };
    dx_ = add(dx_, dx);
    dy_ = add(dy_, dy);
}

Snapshot InputState::sample() {
    Snapshot result{focused_, armed_, {}, 0, 0};
    if (focused_ && armed_ && !awaiting_neutral_) {
        result.held = held_;
        result.mouse_dx = dx_;
        result.mouse_dy = dy_;
    }
    awaiting_neutral_ = false;
    dx_ = dy_ = 0;
    return result;
}

PacketDisposition classify_packet(std::uint32_t queued, std::uint32_t now,
                                  std::uint32_t epoch, std::uint32_t max_age_ms) {
    const auto age = now - queued;
    if (age > max_age_ms) return PacketDisposition::stale;
    // A timestamp equal to the coarse epoch cannot prove it followed arming.
    return age < now - epoch ? PacketDisposition::accept : PacketDisposition::previous_epoch;
}

bool packet_is_fresh(std::uint32_t queued, std::uint32_t now,
                     std::uint32_t epoch, std::uint32_t max_age_ms) {
    return classify_packet(queued, now, epoch, max_age_ms) == PacketDisposition::accept;
}

bool canonical_positive_decimal(std::string_view text, std::uint64_t& value) {
    if (text.empty() || text.front() < '1' || text.front() > '9') return false;
    for (const char c : text) if (c < '0' || c > '9') return false;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size() && value > 0;
}

bool valid_run(std::string_view run) {
    return run.size() == 32 && std::all_of(run.begin(), run.end(), [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}

bool valid_registration_flags(std::uint32_t flags) {
    constexpr std::uint32_t input_sink = 0x00000100;
    constexpr std::uint32_t device_notify = 0x00002000;
    return (flags & ~device_notify) == input_sink;
}

std::string record_json(const RecordIdentity& identity, std::string_view kind,
                        std::uint64_t seq, std::uint64_t utc_ms,
                        std::uint64_t monotonic_ms, const Snapshot& sample,
                        std::string_view reason) {
    std::uint64_t start{};
    if (!valid_run(identity.run) || !identity.target_pid || !seq || !utc_ms ||
        !canonical_positive_decimal(identity.target_start_filetime, start) ||
        (kind != "begin" && kind != "sample" && kind != "end"))
        throw std::invalid_argument("invalid input record identity");
    const bool neutral = !sample.armed &&
        std::none_of(sample.held.begin(), sample.held.end(), [](bool b) { return b; }) &&
        !sample.mouse_dx && !sample.mouse_dy;
    if ((kind != "sample" && (sample.focused || !neutral)) ||
        ((!sample.focused || !sample.armed) && !neutral) ||
        sample.mouse_dx < -32767 || sample.mouse_dx > 32767 ||
        sample.mouse_dy < -32767 || sample.mouse_dy > 32767 ||
        (kind == "begin" && (monotonic_ms != 0 || seq != 1)) ||
        (kind != "end" && !reason.empty()) ||
        (kind == "end" && reason != "duration" && reason != "target_exit" &&
         reason != "write_error" && reason != "shutdown"))
        throw std::invalid_argument("invalid input record state");
    auto boolean = [](bool b) { return b ? "true" : "false"; };
    std::string result = "{\"schema\":1,\"source_kind\":\"windows_raw_input_v1\",\"kind\":\"";
    result += kind;
    result += "\",\"run\":\"" + identity.run + "\",\"seq\":" + std::to_string(seq);
    result += ",\"utc_ms\":" + std::to_string(utc_ms);
    result += ",\"monotonic_ms\":" + std::to_string(monotonic_ms);
    result += ",\"target_pid\":" + std::to_string(identity.target_pid);
    result += ",\"target_start_filetime\":\"" + identity.target_start_filetime + "\"";
    result += ",\"focused\":" + std::string(boolean(sample.focused));
    result += ",\"armed\":" + std::string(boolean(sample.armed)) + ",\"held\":{";
    constexpr std::array<const char*, control_count> names{"forward", "back", "left", "right", "jump", "sprint"};
    for (unsigned i = 0; i < control_count; ++i) {
        if (i) result += ',';
        result += '"'; result += names[i]; result += "\":"; result += boolean(sample.held[i]);
    }
    result += "},\"mouse_dx\":" + std::to_string(sample.mouse_dx);
    result += ",\"mouse_dy\":" + std::to_string(sample.mouse_dy);
    if (kind == "end") result += ",\"reason\":\"" + std::string(reason) + "\"";
    return result + "}\n";
}

} // namespace minecome::input_capture
