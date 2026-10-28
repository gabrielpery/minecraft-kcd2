#pragma once
// Standalone preparation only: not connected to an addon, renderer or controller.
// A single owner serializes calls. Adapters must obtain real, identity-checked
// receipts; this policy validates their scope and completeness, not their truth.
// It neither resets one-shot channels nor grants input/render/engine authority.
#include <algorithm>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>

namespace minecome::hud::rearm {
inline constexpr unsigned maximum_sessions = 2;
inline constexpr std::uint64_t maximum_arm_lease_ms = 180000;
struct Identity {
    std::string run, arm_sha256;
    std::uint32_t target_pid = 0, producer_pid = 0;
    std::uint64_t target_start = 0, producer_start = 0;
    bool operator==(const Identity &) const = default;
};
struct Image {
    std::uint32_t width = 0, height = 0, pitch = 0;
    bool operator==(const Image &) const = default;
};
struct Arm {
    Identity identity;
    Image image;
    std::uint64_t expires_utc_ms = 0;
    bool operator==(const Arm &) const = default;
};
struct Generation {
    unsigned ordinal = 0;
    Arm arm;
    bool operator==(const Generation &) const = default;
};
template<class T> struct Receipt {
    Generation owner;
    std::uint64_t observed_steady_ms = 0;
    T value;
};
struct ClosedInput {
    bool host_closed = false, guest_closed = false;
    std::uint64_t events_sent = 0, events_acknowledged = 0;
};
struct Queues {
    bool snapshot_complete = false;
    std::uint32_t input_pending = 0, world_pending = 0;
    bool pending_world_click = false;
};
struct Renderer {
    bool publication_withdrawn = false, callbacks_retired = false;
    bool resident_generation_retired = false, hidden = false;
};
struct Capture { bool released = false, drained = false, active = false; };
struct Producer { bool exited = false; };
struct ControllerCleanup {
    bool verified = false, aimed_cleanup = false, movement_restored = false, guest_cleanup = false;
    std::string verification_sha256;
};
struct Retirement {
    Receipt<ClosedInput> input;
    Receipt<Queues> queues;
    Receipt<Renderer> renderer;
    Receipt<Capture> capture;
    Receipt<Producer> producer;
    Receipt<ControllerCleanup> controller;
};
enum class Phase { empty, admitted, retiring, idle, exhausted, failed };
enum class Result {
    accepted, explicit_request_required, wrong_phase, session_limit, invalid_arm,
    wrong_target, replayed_arm, reused_producer, image_changed, wrong_generation,
    receipt_identity, receipt_time, incomplete_cleanup, clock_regressed, session_failed
};
enum class Outcome { completed, failed };

class Policy {
public:
    Phase phase() const noexcept { return phase_; }
    // Return an immutable snapshot, never an alias that could acquire the next
    // generation when an asynchronous callback finally checks its old owner.
    Generation current() const { return current_; }
    unsigned admitted_count() const noexcept { return current_.ordinal; }
    std::uint64_t deadline_steady_ms() const noexcept { return deadline_; }
    // Late work is rejected from the moment retirement starts. This predicate
    // is not a freshness check: original channel/input leases remain required.
    bool accepts_callbacks(const Generation &owner) const noexcept {
        return phase_ == Phase::admitted && owner == current_;
    }
    Result admit(const Arm &arm, bool explicit_request, std::uint64_t utc, std::uint64_t steady) {
        if (phase_ == Phase::failed) return Result::session_failed;
        if (phase_ == Phase::exhausted) return Result::session_limit;
        if (phase_ != Phase::empty && phase_ != Phase::idle) return Result::wrong_phase;
        if (!explicit_request) return Result::explicit_request_required;
        if (!steady || (last_steady_ && steady < last_steady_)) return Result::clock_regressed;
        if (!valid(arm, utc) || steady > std::numeric_limits<std::uint64_t>::max() - (arm.expires_utc_ms - utc))
            return Result::invalid_arm;
        if (current_.ordinal) {
            const auto &old = current_.arm.identity;
            const auto &next = arm.identity;
            if (next.target_pid != old.target_pid || next.target_start != old.target_start) return Result::wrong_target;
            if (next.run == old.run || next.arm_sha256 == old.arm_sha256) return Result::replayed_arm;
            // First experiment deliberately excludes recycled producer PIDs.
            if (next.producer_pid == old.producer_pid || next.producer_start <= old.producer_start)
                return Result::reused_producer;
            if (arm.image != current_.arm.image) return Result::image_changed;
        }
        current_ = {current_.ordinal + 1, arm};
        deadline_ = steady + (arm.expires_utc_ms - utc);
        last_steady_ = steady;
        retiring_at_ = 0;
        phase_ = Phase::admitted;
        return Result::accepted;
    }
    Result begin_retirement(const Generation &owner, Outcome outcome, std::uint64_t steady) {
        if (owner != current_) return Result::wrong_generation;
        if (phase_ != Phase::admitted) return Result::wrong_phase;
        if (!steady || steady < last_steady_) { phase_ = Phase::failed; return Result::clock_regressed; }
        last_steady_ = steady;
        if (outcome != Outcome::completed) { phase_ = Phase::failed; return Result::session_failed; }
        retiring_at_ = steady;
        phase_ = Phase::retiring;
        return Result::accepted;
    }
    Result fail(const Generation &owner) noexcept {
        if (owner != current_) return Result::wrong_generation;
        if (phase_ != Phase::admitted && phase_ != Phase::retiring) return Result::wrong_phase;
        phase_ = Phase::failed;
        return Result::session_failed;
    }
    Result retire(const Retirement &proof, std::uint64_t steady) {
        if (phase_ != Phase::retiring) return Result::wrong_phase;
        if (!steady || steady < last_steady_) { phase_ = Phase::failed; return Result::clock_regressed; }
        last_steady_ = steady;
        for (const auto *owner : {&proof.input.owner, &proof.queues.owner, &proof.renderer.owner,
                                 &proof.capture.owner, &proof.producer.owner, &proof.controller.owner})
            if (*owner != current_) return Result::receipt_identity;
        for (const auto observed : {proof.input.observed_steady_ms, proof.queues.observed_steady_ms,
                                   proof.renderer.observed_steady_ms, proof.capture.observed_steady_ms,
                                   proof.producer.observed_steady_ms, proof.controller.observed_steady_ms})
            if (!observed || observed < retiring_at_ || observed > steady) return Result::receipt_time;
        const auto &input = proof.input.value;
        const auto &queues = proof.queues.value;
        const auto &renderer = proof.renderer.value;
        const auto &capture = proof.capture.value;
        const auto &cleanup = proof.controller.value;
        if (!input.host_closed || !input.guest_closed || input.events_sent != input.events_acknowledged ||
            !queues.snapshot_complete || queues.input_pending || queues.world_pending || queues.pending_world_click ||
            !renderer.publication_withdrawn || !renderer.callbacks_retired || !renderer.resident_generation_retired || !renderer.hidden ||
            !capture.released || !capture.drained || capture.active || !proof.producer.value.exited ||
            !cleanup.verified || !cleanup.aimed_cleanup || !cleanup.movement_restored || !cleanup.guest_cleanup ||
            !hex(cleanup.verification_sha256, 64)) return Result::incomplete_cleanup;
        phase_ = current_.ordinal == maximum_sessions ? Phase::exhausted : Phase::idle;
        return Result::accepted;
    }
private:
    static bool hex(std::string_view text, std::size_t length) noexcept {
        return text.size() == length && std::all_of(text.begin(), text.end(), [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        });
    }
    static bool valid(const Arm &arm, std::uint64_t utc) noexcept {
        const auto &id = arm.identity;
        return hex(id.run, 32) && hex(id.arm_sha256, 64) && id.target_pid && id.producer_pid &&
            id.target_pid != id.producer_pid && id.target_start && id.producer_start && utc &&
            arm.expires_utc_ms > utc && arm.expires_utc_ms - utc <= maximum_arm_lease_ms &&
            arm.image.width && arm.image.width <= 1920 && arm.image.height && arm.image.height <= 1080 &&
            arm.image.pitch == arm.image.width * 4;
    }
    Phase phase_ = Phase::empty;
    Generation current_;
    std::uint64_t last_steady_ = 0, retiring_at_ = 0, deadline_ = 0;
};
} // namespace minecome::hud::rearm
