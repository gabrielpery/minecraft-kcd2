#pragma once
#include "stream_contract.hpp"
#include <array>
#include <atomic>
#include <span>

namespace minecome::hud::input {
inline constexpr std::size_t header_bytes=256, ring_count=64, record_bytes=40, mapping_bytes=2816;
inline constexpr std::uint64_t fresh_ms=250, activation_ms=30000;
using Identity=stream::Identity;
enum class Kind : std::uint32_t { key_down=1,key_up=2,move=3,button_down=4,button_up=5,wheel=6 };
struct Event {
    std::uint64_t captured=0;
    Kind kind=Kind::key_down;
    std::uint32_t code=0;
    float x=0,y=0;
    std::int32_t wheel=0;
};
struct Ack {
    std::uint64_t sequence=0,utc=0;
    std::uint32_t state=0,screen=0,selected=0;
};
bool valid_event(const Event &event,std::uint64_t now) noexcept;
bool fresh(std::uint64_t captured,std::uint64_t now) noexcept;
bool valid_key(std::uint32_t code) noexcept;
void encode_host(std::span<std::uint8_t,128> bytes,const Identity &id,std::uint64_t sequence,
                 std::uint64_t utc,std::uint32_t state);
void encode_event(std::span<std::uint8_t,40> bytes,const Event &event,std::uint64_t sequence);
bool decode_ack(std::span<const std::uint8_t,128> bytes,std::uint64_t last,std::uint64_t now,
                const Ack &previous,Ack &ack,std::string &reason,bool require_fresh=true);
// One render producer and one transport worker. No native wait, allocation or
// game call. Overflow is observable and must terminate activation.
class Mailbox {
public:
    bool push(const Event &event) noexcept;
    bool pop(Event &event) noexcept;
    bool overflowed() const noexcept { return overflow_.load(std::memory_order_acquire); }
private:
    std::array<Event,ring_count> events_{};
    std::atomic<std::uint64_t> write_{0},read_{0};
    std::atomic<bool> overflow_{false};
};
// Pure physical-key gate: fresh F8 edge, neutral baseline, two suppressed
// frames before accepting keys, one activation and at most 30 seconds.
class KeyboardGate {
public:
    enum class Step { idle,starting,active,closed };
    enum class Close { none,ineligible,second_f8,clock_regressed,expired,key_during_settle };
    Step update(bool eligible,bool f8,std::uint32_t keys,std::uint64_t now) noexcept;
    bool consumed() const noexcept { return consumed_; }
    bool closed() const noexcept { return closed_; }
    Close close_reason() const noexcept { return reason_; }
private:
    Close reason_=Close::none;
    bool neutral_=false,previous_f8_=false,consumed_=false,closed_=false;
    std::uint32_t settling_=0;
    std::uint64_t began_=0;
};
} // namespace minecome::hud::input
