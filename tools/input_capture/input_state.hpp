#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace minecome::input_capture {

enum class Control : unsigned { forward, back, left, right, jump, sprint, count };
constexpr unsigned control_count = static_cast<unsigned>(Control::count);
using ControlBits = std::array<bool, control_count>;

// Elapsed monotonic milliseconds. A first arm may start the active interval;
// focus loss/rearming can never renew it. Zero wait preserves the old duration.
class CaptureWindow {
public:
    CaptureWindow(unsigned seconds, unsigned arm_wait_seconds);
    bool observe_arm(std::uint64_t elapsed_ms, bool armed);
    bool expired(std::uint64_t elapsed_ms) const { return elapsed_ms >= deadline_ms_; }
    bool waiting() const { return waiting_; }
private:
    std::uint64_t duration_ms_, deadline_ms_;
    bool waiting_;
};

struct Snapshot {
    bool focused{};
    bool armed{};
    ControlBits held{};
    std::int32_t mouse_dx{};
    std::int32_t mouse_dy{};
};

// No platform calls: all methods are used on the capture window's one thread.
class InputState {
public:
    void focus(bool focused, ControlBits currently_down = {}, bool f8_down = false);
    void control(Control key, bool down);
    void f8(bool down);
    void disarm();
    void suppress_currently_down(ControlBits currently_down);
    void suppress_f8_until_release(bool currently_down);
    void relative_mouse(std::int32_t dx, std::int32_t dy);
    Snapshot sample();
    bool focused() const { return focused_; }
    bool armed() const { return armed_; }
    bool awaiting_neutral_sample() const { return awaiting_neutral_; }
private:
    bool focused_{};
    bool armed_{};
    bool f8_down_{};
    bool awaiting_neutral_{};
    ControlBits physical_{};
    ControlBits suppressed_{};
    ControlBits held_{};
    std::int32_t dx_{};
    std::int32_t dy_{};
};

// DWORD tick arithmetic remains correct across wrap for these short intervals.
enum class PacketDisposition { accept, previous_epoch, stale };
PacketDisposition classify_packet(std::uint32_t queued, std::uint32_t now,
                                  std::uint32_t transition_epoch, std::uint32_t max_age_ms = 100);
bool packet_is_fresh(std::uint32_t queued, std::uint32_t now,
                     std::uint32_t transition_epoch, std::uint32_t max_age_ms = 100);
bool canonical_positive_decimal(std::string_view text, std::uint64_t& value);
bool valid_run(std::string_view run);
// Source request uses INPUTSINK|DEVNOTIFY. Measured Windows readback can omit
// DEVNOTIFY; no other additional/alternate flag is accepted.
bool valid_registration_flags(std::uint32_t flags);

struct RecordIdentity {
    std::string run;
    std::uint32_t target_pid{};
    std::string target_start_filetime;
};
// Throws for invalid identity/kind/reason/neutral or timing invariants.
std::string record_json(const RecordIdentity& identity, std::string_view kind,
                        std::uint64_t seq, std::uint64_t utc_ms,
                        std::uint64_t monotonic_ms, const Snapshot& sample,
                        std::string_view end_reason = {});

} // namespace minecome::input_capture
