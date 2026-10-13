#pragma once
// Original bounded physical-button policy. No OS input, engine calls or IO.
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace minecome::hud::world {
inline constexpr std::uint64_t max_clicks=16;
struct Click {
    std::uint64_t sequence=0,utc=0,ui_sequence=0;
    std::uint32_t action=0;
    std::uintptr_t window=0;
    std::uint64_t token=0,generation=0;
};
class Gate {
public:
    enum class Failure { none,simultaneous_buttons,invalid_buttons,clock,capacity };
    // Every entry into a ready world requires two neutral captured frames.
    // An inventory/transition press remains ineligible until physically released.
    Click update(bool world_ready,unsigned buttons,std::uint64_t utc,std::uint64_t steady,std::uint64_t ui_sequence) noexcept {
        if(failure_!=Failure::none)return {};
        if(!utc||(observed_&&steady<last_steady_)){failure_=Failure::clock;return {};}
        observed_=true;last_steady_=steady;
        if(!world_ready){suspend();return {};}
        if(buttons&~3u){failure_=Failure::invalid_buttons;return {};}
        if(buttons==3){failure_=Failure::simultaneous_buttons;return {};}
        if(!active_){
            if(buttons){neutral_=0;return {};}
            if(++neutral_>=2)active_=true;
            return {};
        }
        if(buttons==held_)return {};
        const auto previous=held_;held_=buttons;
        if(!buttons)return {};
        // A sampled change from one held button to the other is not a neutral
        // baseline. Suppress both until a clean release/rearm has been observed.
        if(previous){suspend();return {};}
        if(sequence_==max_clicks){failure_=Failure::capacity;return {};}
        return {++sequence_,utc,ui_sequence,buttons==2?1u:2u};
    }
    void suspend() noexcept {neutral_=held_=0;active_=false;}
    bool active()const noexcept{return active_;}
    Failure failure()const noexcept{return failure_;}
    std::uint64_t sequence()const noexcept{return sequence_;}
private:
    std::uint64_t sequence_=0,last_steady_=0;
    unsigned neutral_=0,held_=0;
    bool active_=false,observed_=false;
    Failure failure_=Failure::none;
};

// One render producer and one service-worker consumer. A full queue is terminal;
// neither side waits or allocates, and records are never replaced or replayed.
class Queue {
public:
    bool push(Click click) noexcept {
        const auto write=write_.load(std::memory_order_relaxed);
        if(write-read_.load(std::memory_order_acquire)>=records_.size()){
            overflow_.store(true,std::memory_order_release);return false;
        }
        records_[write%records_.size()]=click;write_.store(write+1,std::memory_order_release);return true;
    }
    bool pop(Click &click) noexcept {
        const auto read=read_.load(std::memory_order_relaxed);
        if(read==write_.load(std::memory_order_acquire))return false;
        click=records_[read%records_.size()];read_.store(read+1,std::memory_order_release);return true;
    }
    bool overflowed()const noexcept{return overflow_.load(std::memory_order_acquire);}
private:
    std::array<Click,max_clicks> records_{};
    std::atomic<std::uint64_t> write_{0},read_{0};
    std::atomic<bool> overflow_{false};
};
enum class Delivery { wait,drop,emit };
inline bool capture_matches(const Click &click,bool active,std::uint64_t token,std::uint64_t generation) noexcept {
    return active&&click.window&&click.token&&click.generation&&click.token==token&&click.generation==generation;
}
inline Delivery delivery(const Click &click,bool live,std::uint64_t now,std::uint64_t ack_sequence,unsigned screen) noexcept {
    if(!live||screen!=0||click.sequence==0||click.sequence>max_clicks||click.action<1||click.action>2||
       click.utc==0||click.utc>now||now-click.utc>250)return Delivery::drop;
    return ack_sequence<click.ui_sequence?Delivery::wait:Delivery::emit;
}
} // namespace minecome::hud::world
