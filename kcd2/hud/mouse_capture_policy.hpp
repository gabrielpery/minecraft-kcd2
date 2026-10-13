#pragma once
#include "mouse_capture_api.hpp"
#include <array>
#include <cstddef>
namespace minecome::mouse {
// Transport-independent policy. The adapter serializes this fixed-size state;
// no allocation, COM call, clock read or Windows API occurs here.
class Policy {
public:
    struct Device {
        std::uintptr_t key=0,window=0;
        std::uint32_t bytes=0;
        bool relative=false,hooks=false,pending=false,fault=false;
    };
    struct Ticket {std::uintptr_t key=0;std::uint64_t generation=0;bool suppress=false;};
    void add(std::uintptr_t key,bool hooks) {
        if(find(key))return;
        invalidate(Reason::configuration_changed);
        for(auto &d:devices_)if(!d.key){d.key=key;d.hooks=hooks;return;}
        overflow_=true;reason_=Reason::capacity;
    }
    void remove(std::uintptr_t key) {
        if(auto *d=find(key)){invalidate(Reason::device_removed);*d={};}
    }
    void format(std::uintptr_t key,std::uint32_t bytes,bool relative) {
        if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->bytes=bytes;d->relative=relative;}
    }
    void axis(std::uintptr_t key,bool relative) {
        if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->relative=relative;}
    }
    void cooperative(std::uintptr_t key,std::uintptr_t window) {
        if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->window=window;}
    }
    void unsupported(std::uintptr_t key) {
        if(auto *d=find(key)){invalidate(Reason::unsupported_device);d->fault=true;}
    }
    void invalidate(Reason why) {
        if(active_)for(auto &d:devices_)if(d.key&&d.window==window_)d.pending=true;
        active_=false;deadline_=0;reason_=why;++generation_;
    }
    void tick(std::uint64_t now,bool window_valid) {
        if(active_&&(!window_valid||now>=deadline_))invalidate(window_valid?Reason::lease_expired:Reason::foreground);
    }
    Result request(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,std::uint64_t now,bool window_valid) {
        if(!window||!token||!duration||duration>max_lease_ms)return Result::bad_argument;
        if((active_||pending())&&(window!=window_||token!=token_))return Result::foreign_owner;
        tick(now,window_valid);
        if(!window_valid){reason_=Reason::foreground;return Result::unavailable;}
        if(pending())return Result::draining;
        const auto why=eligibility(window);
        if(why!=Reason::none){reason_=why;return Result::unavailable;}
        if(!active_)++generation_;
        window_=window;token_=token;deadline_=now+duration;active_=true;reason_=Reason::none;return Result::ok;
    }
    Result release(std::uintptr_t window,std::uint64_t token) {
        if(!window||!token)return Result::bad_argument;
        if(window!=window_||token!=token_)return Result::foreign_owner;
        if(active_)invalidate(Reason::released);
        return Result::ok;
    }
    Ticket begin(std::uintptr_t key,std::uint64_t now,bool window_valid) {
        tick(now,window_valid);
        auto *d=find(key);
        return {key,generation_,d&&((active_&&d->window==window_)||d->pending)};
    }
    void finish(Ticket ticket,bool drained,bool state,bool peek) {
        if(!ticket.suppress)return;
        if(state)++state_suppressions_;else{++data_suppressions_;if(peek)++peek_suppressions_;}
        if(!drained){++drain_failures_;invalidate(Reason::drain_failed);if(auto *d=find(ticket.key))d->fault=true;return;}
        ++queue_drains_;
        // A concurrent release/reconfiguration retains its pending drain; this
        // old in-flight sample cannot certify a newer ownership generation.
        if(ticket.generation==generation_)if(auto *d=find(ticket.key))d->pending=false;
    }
    Snapshot snapshot(std::uintptr_t window,std::uint64_t now,bool window_valid) {
        tick(now,window_valid);Snapshot out;out.generation=generation_;out.token=token_;out.reason=static_cast<std::uint32_t>(reason_);
        for(const auto &d:devices_)if(d.key){++out.device_count;if(good(d,window))++out.eligible_devices;}
        if(window_valid&&!pending()&&eligibility(window)==Reason::none)out.flags|=Flag::eligible;
        if(active_&&window==window_){out.flags|=Flag::active;out.lease_remaining_ms=deadline_-now;}
        if(pending())out.flags|=Flag::draining;
        out.state_suppressions=state_suppressions_;out.data_suppressions=data_suppressions_;out.peek_suppressions=peek_suppressions_;
        out.queue_drains=queue_drains_;out.drain_failures=drain_failures_;return out;
    }
    std::uintptr_t window()const{return window_;}
    bool known(std::uintptr_t key)const {for(const auto &d:devices_)if(d.key==key&&key)return true;return false;}
    std::uint32_t bytes(std::uintptr_t key)const {for(const auto &d:devices_)if(d.key==key&&key)return d.bytes;return 0;}
    bool safe_relative(std::uintptr_t key)const {for(const auto &d:devices_)if(d.key==key&&key)return (d.bytes==16||d.bytes==20)&&d.relative;return false;}
private:
    std::array<Device,16> devices_{};
    std::uintptr_t window_=0;std::uint64_t token_=0,deadline_=0,generation_=1;
    std::uint64_t state_suppressions_=0,data_suppressions_=0,peek_suppressions_=0,queue_drains_=0,drain_failures_=0;
    bool active_=false,overflow_=false;Reason reason_=Reason::no_device;
    Device *find(std::uintptr_t key){for(auto &d:devices_)if(d.key==key&&key)return &d;return nullptr;}
    static bool good(const Device &d,std::uintptr_t window){return d.window==window&&d.hooks&&(d.bytes==16||d.bytes==20)&&d.relative&&!d.fault;}
    bool pending()const{for(const auto &d:devices_)if(d.pending)return true;return false;}
    Reason eligibility(std::uintptr_t window)const {
        if(overflow_)return Reason::capacity;
        bool found=false;
        for(const auto &d:devices_)if(d.key){
            if(!d.window)return Reason::cooperative_window;
            if(d.window!=window)return Reason::cooperative_window;
            found=true;
            if(!d.hooks||d.fault)return Reason::unsupported_device;
            if(d.bytes!=16&&d.bytes!=20)return Reason::layout;
            if(!d.relative)return Reason::axis_mode;
        }
        return found?Reason::none:Reason::no_device;
    }
};
} // namespace minecome::mouse
