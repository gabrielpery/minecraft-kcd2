#include "input_channel.hpp"
#include <algorithm>
#include <cstring>

namespace minecome::hud::input {
Writer::~Writer() {if(mapped_&&status_.state!=2)finish("host_shutdown");dispose();}
void Writer::dispose() {if(mapped_){UnmapViewOfFile(mapped_);mapped_=nullptr;}mapping_.reset();mutex_.reset();producer_.reset();}
bool Writer::create(const Identity &id) {
    if(consumed_)return false;consumed_=true;
    const auto utc=stream::utc_ms();begun_=stream::steady_ms();
    if(!stream::valid_identity(id)||id.target_pid!=GetCurrentProcessId()||id.target_start!=stream::process_start()||
        id.expires_utc_ms<=utc||id.expires_utc_ms-utc>stream::max_lease_ms) {reason_="host_identity_or_expiry";return false;}
    identity_=id;deadline_=begun_+(id.expires_utc_ms-utc);
    producer_.reset(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,id.producer_pid));
    if(!producer_||stream::process_start(producer_.value)!=id.producer_start||WaitForSingleObject(producer_.value,0)!=WAIT_TIMEOUT) {
        reason_="guest_process_identity";dispose();return false;
    }
    const std::wstring token(id.run.begin(),id.run.end());
    mapping_.reset(CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,mapping_bytes,(L"Local\\MineComeHudInput_"+token).c_str()));
    if(!mapping_||GetLastError()==ERROR_ALREADY_EXISTS) {reason_="mapping_exists_or_failed";dispose();return false;}
    mutex_.reset(CreateMutexW(nullptr,TRUE,(L"Local\\MineComeHudInputLock_"+token).c_str()));
    if(!mutex_||GetLastError()==ERROR_ALREADY_EXISTS) {reason_="mutex_exists_or_failed";dispose();return false;}
    mapped_=static_cast<std::uint8_t *>(MapViewOfFile(mapping_.value,FILE_MAP_WRITE|FILE_MAP_READ,0,0,mapping_bytes));
    if(!mapped_) {ReleaseMutex(mutex_.value);reason_="mapping_view_failed";dispose();return false;}
    std::memset(mapped_,0,mapping_bytes);encode_host(owned_,id,0,utc,0);std::memcpy(mapped_,owned_.data(),128);
    if(!ReleaseMutex(mutex_.value)) {reason_="mutex_release_failed";dispose();return false;}
    status_.live=true;return true;
}
bool Writer::ready() const {
    return status_.live&&status_.state<2&&status_.ack.state==1&&fresh(status_.ack.utc,stream::utc_ms())&&
        stream::steady_ms()>=status_.observed&&stream::steady_ms()-status_.observed<=fresh_ms;
}
bool Writer::poll() {return transact({});}
bool Writer::arm() {
    if(!ready()||status_.state!=0)return false;
    status_.state=1;return transact({});
}
bool Writer::append(std::span<const Event> events) {
    if(events.empty())return true;
    if(!ready()||status_.state!=1) {finish("input_not_ready");return false;}
    return transact(events);
}
void Writer::finish(std::string_view reason) {
    if(status_.state==2)return;
    reason_=reason;status_.state=2;status_.live=false;
    transact({},true);
}
bool Writer::transact(std::span<const Event> events,bool closing) {
    if(!mapped_)return false;
    const auto utc=stream::utc_ms(),steady=stream::steady_ms();
    if(!closing&&status_.state!=2) {
        if(utc>=identity_.expires_utc_ms||steady<begun_||steady>=deadline_) {finish("expired");return false;}
        if(WaitForSingleObject(producer_.value,0)!=WAIT_TIMEOUT) {finish("guest_exited");return false;}
    }
    const DWORD wait=WaitForSingleObject(mutex_.value,5);
    if(wait==WAIT_TIMEOUT) {
        return events.empty(); // Caller retains unsent events; never drop an edge.
    }
    if(wait==WAIT_ABANDONED) {
        status_.state=2;status_.live=false;reason_="mutex_abandoned";
        encode_host(owned_,identity_,status_.sequence,utc,2);std::memcpy(mapped_,owned_.data(),128);ReleaseMutex(mutex_.value);return false;
    }
    if(wait!=WAIT_OBJECT_0) {status_.state=2;status_.live=false;reason_="mutex_failed";return false;}
    bool valid=true;
    if(std::memcmp(mapped_,owned_.data(),128)!=0) {reason_="host_bytes_changed";valid=false;}
    const auto received_utc=stream::utc_ms();
    const auto received_steady=stream::steady_ms();
    // A worker may be descheduled while acquiring the mutex. The immutable
    // lease must still be live at the point events are committed to the ring.
    if(valid&&status_.state!=2&&(received_utc>=identity_.expires_utc_ms||received_steady<begun_||received_steady>=deadline_)) {
        reason_="expired";valid=false;
    }
    Ack ack;std::string ack_error;
    // Only an armed host owns input. An old but structurally valid ready ACK
    // before F8 makes ready() false; a real fresh client tick may recover. A
    // closed host may also wait for its final ACK without renewing ownership.
    if(valid&&!decode_ack(std::span<const std::uint8_t,128>(mapped_+128,128),status_.sequence,received_utc,
                         status_.ack,ack,ack_error,status_.state==1)) {
        reason_=ack_error;valid=false;
        status_.rejected_at_utc_ms=received_utc;status_.rejected_ack_utc_ms=0;
        for(unsigned i=0;i<8;++i)status_.rejected_ack_utc_ms|=std::uint64_t(mapped_[136+i])<<(i*8);
        status_.rejected_host_state=status_.state;
    }
    if(valid) {
        status_.ack=ack;status_.observed=stream::steady_ms();
        if(status_.state==0&&ack.state==1) {
            const auto age=received_utc>=ack.utc?received_utc-ack.utc:0;
            status_.max_prearm_ack_age_ms=std::max(status_.max_prearm_ack_age_ms,age);
            const bool old=age>fresh_ms;
            if(old)++status_.prearm_stale_observations;
            if(prearm_was_old_&&!old)++status_.prearm_recoveries;
            prearm_was_old_=old;
        }
    }
    if(valid&&ack.state==2&&status_.state!=2) {reason_="guest_closed";valid=false;}
    if(valid&&status_.state==1&&(!fresh(ack.utc,received_utc)||ack.state!=1)) {reason_="ack_not_ready";valid=false;}
    if(valid&&events.size()>ring_count-(status_.sequence-ack.sequence)) {reason_="ring_overflow";valid=false;}
    if(valid)for(const auto &event:events)if(!valid_event(event,received_utc)){reason_="invalid_or_stale_event";valid=false;break;}
    if(!valid) {status_.state=2;status_.live=false;}
    if(valid&&status_.state==1)for(const auto &event:events) {
        ++status_.sequence;
        encode_event(std::span<std::uint8_t,40>(mapped_+header_bytes+((status_.sequence-1)%ring_count)*record_bytes,40),event,status_.sequence);
    }
    encode_host(owned_,identity_,status_.sequence,received_utc,status_.state);std::memcpy(mapped_,owned_.data(),128);
    if(!ReleaseMutex(mutex_.value)) {status_.state=2;status_.live=false;reason_="mutex_release_failed";return false;}
    return valid;
}
} // namespace minecome::hud::input
