#pragma once
#include "mouse_capture_api.hpp"
#include <array>
#include <atomic>
namespace minecome::mouse {
struct Notice { const char *event=nullptr; Result result=Result::unavailable; Snapshot snapshot; };
// Producers are serialized by the addon's existing runtime mutex; one worker
// consumes. No allocation, waiting, formatting or file I/O on render callbacks.
class Notices {
public:
    bool push(Notice notice) noexcept {
        const auto write=write_.load(std::memory_order_relaxed);
        if(write-read_.load(std::memory_order_acquire)>=records_.size()){
            dropped_.fetch_add(1,std::memory_order_relaxed);return false;
        }
        records_[write%records_.size()]=notice;write_.store(write+1,std::memory_order_release);return true;
    }
    bool pop(Notice &notice) noexcept {
        const auto read=read_.load(std::memory_order_relaxed);
        if(read==write_.load(std::memory_order_acquire))return false;
        notice=records_[read%records_.size()];read_.store(read+1,std::memory_order_release);return true;
    }
    std::uint64_t take_dropped() noexcept {return dropped_.exchange(0,std::memory_order_acq_rel);}
private:
    static_assert(std::atomic<std::uint64_t>::is_always_lock_free);
    std::array<Notice,32> records_{};
    std::atomic<std::uint64_t> write_{0},read_{0},dropped_{0};
};
}
