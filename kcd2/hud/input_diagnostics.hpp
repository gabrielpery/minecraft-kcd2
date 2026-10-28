#pragma once
#include <atomic>
#include <cstdint>
namespace minecome::hud::input {
enum class CloseCause : std::uint32_t {
    none,eligibility_lost,second_f8,clock_regressed,activation_expired,key_during_settle,
    overlay_open,runtime_reload,runtime_destroy,runtime_lock_contention,callback_exception,
    mailbox_overflow,session_end,render_stale,worker_terminal,mouse_capture,mouse_transition
};
enum class WindowCheck : std::uint32_t {
    runtime_handle=1,valid_handle=2,owned_process=4,not_minimized=8,visible=16,foreground=32
};
struct WindowSnapshot {
    std::uint32_t checked=0,failed=0,foreground_pid=0;
    bool foreground_pid_sampled=false;
    bool record(WindowCheck check,bool passed) noexcept {
        const auto bit=static_cast<std::uint32_t>(check);
        checked|=bit;if(!passed)failed|=bit;return passed;
    }
    // Preserve short-circuit evidence: an unexecuted Win32 query is unknown,
    // never a false result. These strings serialize directly as JSON values.
    const char *value(WindowCheck check) const noexcept {
        const auto bit=static_cast<std::uint32_t>(check);
        return !(checked&bit)?"null":(failed&bit)?"false":"true";
    }
};
struct CloseSnapshot {
    CloseCause cause=CloseCause::none;
    std::uint32_t eligibility_failures=0,composition_stage=0,held_keys=0;
    bool f8=false;
    std::uint64_t utc=0,ack_utc=0,ack_observed_age=0,publication_age=0,resident_age=0;
    bool eligibility_sampled=false;
    WindowSnapshot window;
    bool activation_age_valid=false;
    std::uint64_t activation_age_ms=0;
};
// Exactly one immutable snapshot per owner lifetime. The writing sentinel
// prevents competing callbacks from racing plain fields. No wait/allocation.
class FirstClose {
public:
    bool publish(const CloseSnapshot &value) noexcept {
        unsigned empty=0;
        if(!state_.compare_exchange_strong(empty,1,std::memory_order_acq_rel))return false;
        value_=value;state_.store(2,std::memory_order_release);return true;
    }
    bool read(CloseSnapshot &value) const noexcept {
        if(state_.load(std::memory_order_acquire)!=2)return false;
        value=value_;return true;
    }
private:
    static_assert(std::atomic<unsigned>::is_always_lock_free);
    std::atomic<unsigned> state_{0};
    CloseSnapshot value_;
};
inline const char *close_name(CloseCause cause) noexcept {
    switch(cause) {
    case CloseCause::none:return "none";
    case CloseCause::eligibility_lost:return "eligibility_lost";
    case CloseCause::second_f8:return "second_f8";
    case CloseCause::clock_regressed:return "clock_regressed";
    case CloseCause::activation_expired:return "activation_expired";
    case CloseCause::key_during_settle:return "key_during_settle";
    case CloseCause::overlay_open:return "overlay_open";
    case CloseCause::runtime_reload:return "runtime_reload";
    case CloseCause::runtime_destroy:return "runtime_destroy";
    case CloseCause::runtime_lock_contention:return "runtime_lock_contention";
    case CloseCause::callback_exception:return "callback_exception";
    case CloseCause::mailbox_overflow:return "mailbox_overflow";
    case CloseCause::session_end:return "session_end";
    case CloseCause::render_stale:return "render_stale";
    case CloseCause::worker_terminal:return "worker_terminal";
    case CloseCause::mouse_capture:return "mouse_capture";
    case CloseCause::mouse_transition:return "mouse_transition";
    }
    return "unknown";
}
} // namespace minecome::hud::input
