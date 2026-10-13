#pragma once
#include "selective_capture_api.hpp"
#include <array>
#include <algorithm>
namespace minecome::selective {
// Virtual buffered queue preserves the caller's PEEK/non-PEEK/count/discard
// semantics after physical button records have been removed. No allocation.
struct Record {std::uint32_t offset=0,data=0,time=0,sequence=0;std::uintptr_t app=0;};
class Buffer {
public:
    static constexpr std::size_t capacity=256;
    std::size_t size()const noexcept{return count_;}
    std::size_t free()const noexcept{return capacity-count_;}
    bool push(Record value)noexcept{if(count_==capacity)return false;items_[(head_+count_)%capacity]=value;++count_;return true;}
    const Record &at(std::size_t index)const noexcept{return items_[(head_+index)%capacity];}
    void consume(std::size_t count)noexcept{count=std::min(count,count_);head_=(head_+count)%capacity;count_-=count;}
    void clear()noexcept{head_=count_=0;overflow=false;}
    bool overflow=false;
private:std::array<Record,capacity> items_{};std::size_t head_=0,count_=0;
};
class Policy {
public:
    struct Device {std::uintptr_t key=0,window=0;std::uint32_t bytes=0;bool relative=false,hooks=false,pending=false,fault=false,busy=false;Buffer buffer;};
    struct Ticket {std::uintptr_t key=0;std::uint64_t generation=0;Mode mode=Mode::none;bool suppress=false,owned=false;};
    void add(std::uintptr_t key,bool hooks){if(find(key))return;invalidate(Reason::configuration_changed);for(auto &d:devices_)if(!d.key){d.key=key;d.hooks=hooks;return;}overflow_=true;reason_=Reason::capacity;}
    void remove(std::uintptr_t key){if(auto *d=find(key)){invalidate(Reason::device_removed);*d={};}}
    void format(std::uintptr_t key,std::uint32_t bytes,bool relative){if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->bytes=bytes;d->relative=relative;d->buffer.clear();}}
    void axis(std::uintptr_t key,bool relative){if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->relative=relative;}}
    void cooperative(std::uintptr_t key,std::uintptr_t window){if(auto *d=find(key)){invalidate(Reason::configuration_changed);d->window=window;}}
    void unsupported(std::uintptr_t key,Reason why=Reason::unsupported_device){if(auto *d=find(key)){invalidate(why);d->fault=true;}}
    void invalidate(Reason why){if(active_)mark_pending();active_=false;deadline_=0;mode_=Mode::none;reason_=why;++generation_;}
    void tick(std::uint64_t now,bool valid){if(active_&&(!valid||now>=deadline_))invalidate(valid?Reason::lease_expired:Reason::foreground);}
    Result request(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,Mode desired,std::uint64_t now,bool valid){
        if(!window||!token||!duration||duration>max_lease_ms||(desired!=Mode::full&&desired!=Mode::buttons))return Result::bad_argument;
        if((active_||pending())&&(window!=window_||token!=token_))return Result::foreign_owner;
        tick(now,valid);
        if(!valid){reason_=Reason::foreground;return Result::unavailable;}
        if(pending()){
            if(!active_)return Result::draining;
            if(desired!=requested_)return Result::bad_argument;
            deadline_=now+duration;return Result::draining;
        }
        const auto why=eligibility(window);if(why!=Reason::none){reason_=why;return Result::unavailable;}
        if(active_&&mode_!=desired){mark_pending();mode_=Mode::full;requested_=desired;++generation_;reason_=Reason::mode_changed;deadline_=now+duration;return Result::draining;}
        if(!active_)++generation_;
        window_=window;token_=token;deadline_=now+duration;active_=true;mode_=requested_=desired;reason_=Reason::none;return Result::ok;
    }
    Result release(std::uintptr_t window,std::uint64_t token){if(!window||!token)return Result::bad_argument;if(window!=window_||token!=token_)return Result::foreign_owner;if(active_)invalidate(Reason::released);return Result::ok;}
    Ticket begin(std::uintptr_t key,std::uint64_t now,bool valid){
        tick(now,valid);auto *d=find(key);if(!d||!((active_&&d->window==window_)||d->pending))return {};
        if(d->busy){unsupported(key,Reason::concurrent_io);return {key,generation_,Mode::full,true,false};}
        d->busy=true;return {key,generation_,d->pending?Mode::full:mode_,true,true};
    }
    bool current(Ticket t)const noexcept{return t.owned&&t.generation==generation_;}
    void finish(Ticket t,bool success,bool state,bool peek,bool drained){
        if(!t.owned)return;auto *d=find(t.key);if(!d)return;d->busy=false;
        if(state)++state_suppressions_;else{++data_suppressions_;if(peek)++peek_suppressions_;}
        if(!success){++drain_failures_;unsupported(t.key,Reason::drain_failed);return;}
        if(drained){++queue_drains_;d->buffer.clear();if(t.generation==generation_)d->pending=false;}
        if(active_&&!pending()&&mode_!=requested_){mode_=requested_;reason_=Reason::none;}
    }
    Snapshot snapshot(std::uintptr_t window,std::uint64_t now,bool valid){
        tick(now,valid);Snapshot out;out.generation=generation_;out.token=token_;out.reason=static_cast<unsigned>(reason_);
        for(const auto &d:devices_)if(d.key){++out.device_count;if(good(d,window))++out.eligible_devices;}
        if(valid&&!pending()&&eligibility(window)==Reason::none)out.flags|=eligible;
        if(active_&&window==window_){out.flags|=active;out.lease_remaining_ms=deadline_-now;out.mode=mode_;}
        if(pending())out.flags|=draining;
        out.state_suppressions=state_suppressions_;out.data_suppressions=data_suppressions_;out.peek_suppressions=peek_suppressions_;out.queue_drains=queue_drains_;out.drain_failures=drain_failures_;
        out.axis_records_delivered=axis_records_delivered_;out.button_records_filtered=button_records_filtered_;out.buffer_overflows=buffer_overflows_;return out;
    }
    void delivered(std::uint64_t count){axis_records_delivered_+=count;}
    void filtered(){++button_records_filtered_;}
    void overflow(){++buffer_overflows_;}
    std::uintptr_t window()const{return window_;}
    bool known(std::uintptr_t key)const{return find(key)!=nullptr;}
    std::uint32_t bytes(std::uintptr_t key)const{const auto *d=find(key);return d?d->bytes:0;}
    bool safe_relative(std::uintptr_t key)const{const auto *d=find(key);return d&&(d->bytes==16||d->bytes==20)&&d->relative;}
    Buffer *buffer(std::uintptr_t key){auto *d=find(key);return d?&d->buffer:nullptr;}
private:
    std::array<Device,16> devices_{};std::uintptr_t window_=0;
    std::uint64_t token_=0,deadline_=0,generation_=1,state_suppressions_=0,data_suppressions_=0,peek_suppressions_=0,queue_drains_=0,drain_failures_=0,axis_records_delivered_=0,button_records_filtered_=0,buffer_overflows_=0;
    bool active_=false,overflow_=false;Mode mode_=Mode::none,requested_=Mode::none;Reason reason_=Reason::no_device;
    Device *find(std::uintptr_t key){for(auto &d:devices_)if(key&&d.key==key)return &d;return nullptr;}
    const Device *find(std::uintptr_t key)const{for(const auto &d:devices_)if(key&&d.key==key)return &d;return nullptr;}
    void mark_pending(){for(auto &d:devices_)if(d.key&&d.window==window_)d.pending=true;}
    bool pending()const{for(const auto &d:devices_)if(d.pending)return true;return false;}
    static bool good(const Device &d,std::uintptr_t window){return d.window==window&&d.hooks&&(d.bytes==16||d.bytes==20)&&d.relative&&!d.fault;}
    Reason eligibility(std::uintptr_t window)const{
        if(overflow_)return Reason::capacity;bool found=false;
        for(const auto &d:devices_)if(d.key){if(!d.window||d.window!=window)return Reason::cooperative_window;found=true;if(!d.hooks||d.fault)return Reason::unsupported_device;if(d.bytes!=16&&d.bytes!=20)return Reason::layout;if(!d.relative)return Reason::axis_mode;}
        return found?Reason::none:Reason::no_device;
    }
};
}
