#include "input_contract.hpp"
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstring>

namespace minecome::hud::input {
namespace {
void put32(std::span<std::uint8_t> b,std::size_t at,std::uint32_t value) { for(unsigned i=0;i<4;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8)); }
void put64(std::span<std::uint8_t> b,std::size_t at,std::uint64_t value) { for(unsigned i=0;i<8;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8)); }
std::uint32_t get32(std::span<const std::uint8_t> b,std::size_t at) { std::uint32_t v=0;for(unsigned i=0;i<4;++i)v|=std::uint32_t(b[at+i])<<(i*8);return v; }
std::uint64_t get64(std::span<const std::uint8_t> b,std::size_t at) { std::uint64_t v=0;for(unsigned i=0;i<8;++i)v|=std::uint64_t(b[at+i])<<(i*8);return v; }
}
bool valid_key(std::uint32_t code,Profile profile) noexcept {
    if(profile!=Profile::ui&&profile!=Profile::movement)return false;
    return (code>=0x31&&code<=0x39)||code==0x45||code==0x1b||
        (profile==Profile::movement&&(code==0x57||code==0x41||code==0x53||code==0x44||code==0x20));
}
bool fresh(std::uint64_t timestamp,std::uint64_t now) noexcept {
    return timestamp && (timestamp<=now ? now-timestamp<=fresh_ms : timestamp-now<=100);
}
bool valid_event(const Event &e,std::uint64_t now,Profile profile) noexcept {
    if(profile!=Profile::ui&&profile!=Profile::movement)return false;
    if(!fresh(e.captured,now)||!std::isfinite(e.x)||!std::isfinite(e.y)||e.x<0||e.x>1||e.y<0||e.y>1)return false;
    switch(e.kind) {
    case Kind::key_down:case Kind::key_up:return valid_key(e.code,profile)&&e.x==0&&e.y==0&&e.wheel==0;
    case Kind::move:return e.code==0&&e.wheel==0;
    case Kind::button_down:case Kind::button_up:return e.code<=1&&e.wheel==0;
    case Kind::wheel:return e.code==0&&e.wheel>=-16&&e.wheel<=16&&e.wheel!=0;
    default:return false;
    }
}
void encode_host(std::span<std::uint8_t,128> b,const Identity &id,std::uint64_t sequence,std::uint64_t utc,std::uint32_t state,Profile profile) {
    std::fill(b.begin(),b.end(),std::uint8_t{0});std::memcpy(b.data(),profile==Profile::movement?"MCHUDI02":"MCHUDI01",8);put32(b,8,static_cast<std::uint32_t>(profile));put32(b,12,mapping_bytes);
    std::memcpy(b.data()+16,id.run.data(),32);put32(b,48,id.producer_pid);put32(b,52,id.target_pid);
    put64(b,56,id.producer_start);put64(b,64,id.target_start);put64(b,72,id.expires_utc_ms);
    put64(b,80,sequence);put64(b,88,utc);put32(b,96,state);put32(b,100,static_cast<std::uint32_t>(std::min<std::uint64_t>(sequence,64)));
}
void encode_event(std::span<std::uint8_t,40> b,const Event &e,std::uint64_t sequence) {
    std::fill(b.begin(),b.end(),std::uint8_t{0});put64(b,0,sequence);put64(b,8,e.captured);put32(b,16,static_cast<std::uint32_t>(e.kind));
    put32(b,20,e.code);put32(b,24,std::bit_cast<std::uint32_t>(e.x));put32(b,28,std::bit_cast<std::uint32_t>(e.y));
    put32(b,32,std::bit_cast<std::uint32_t>(e.wheel));
}
bool decode_ack(std::span<const std::uint8_t,128> b,std::uint64_t last,std::uint64_t now,
                const Ack &previous,Ack &ack,std::string &reason,bool require_fresh) {
    auto fail=[&](const char *why){reason=why;return false;};
    if(std::any_of(b.begin()+28,b.end(),[](auto v){return v!=0;}))return fail("ack_reserved");
    Ack next{get64(b,0),get64(b,8),get32(b,16),get32(b,20),get32(b,24)};
    if(next.state>2||next.screen>1||next.selected>8||next.sequence>last||next.sequence<previous.sequence)return fail("ack_fields");
    if(next.state<previous.state)return fail("ack_regressed");
    if(next.state==0) {
        if(next.sequence||next.utc||next.screen||next.selected)return fail("ack_waiting_nonzero");
    } else {
        if(!next.utc)return fail("ack_timestamp_zero");
        if(next.utc>now&&next.utc-now>100)return fail("ack_future");
        if(next.utc<previous.utc)return fail("ack_time_regressed");
        if(require_fresh&&next.utc<=now&&now-next.utc>fresh_ms)return fail("ack_aged");
    }
    ack=next;reason.clear();return true;
}
bool Mailbox::push(const Event &e) noexcept {
    const auto w=write_.load(std::memory_order_relaxed),r=read_.load(std::memory_order_acquire);
    if(w-r>=ring_count) {overflow_.store(true,std::memory_order_release);return false;}
    events_[w%ring_count]=e;write_.store(w+1,std::memory_order_release);return true;
}
bool Mailbox::pop(Event &e) noexcept {
    const auto r=read_.load(std::memory_order_relaxed),w=write_.load(std::memory_order_acquire);
    if(r==w)return false;e=events_[r%ring_count];read_.store(r+1,std::memory_order_release);return true;
}
KeyboardGate::Step KeyboardGate::update(bool eligible,bool f8,std::uint32_t keys,std::uint64_t now) noexcept {
    const bool edge=f8&&!previous_f8_;previous_f8_=f8;
    if(closed_)return Step::closed;
    if(!consumed_) {
        if(!eligible) {neutral_=false;return Step::idle;}
        if(!f8&&!keys)neutral_=true;
        if(!edge)return Step::idle;
        if(!neutral_||keys)return Step::idle;
        consumed_=true;began_=now;settling_=2;return Step::starting;
    }
    if(!eligible||edge||now<began_||now-began_>=activation_ms) {
        reason_=!eligible?Close::ineligible:edge?Close::second_f8:now<began_?Close::clock_regressed:Close::expired;
        closed_=true;return Step::closed;
    }
    if(settling_) {--settling_;if(keys) {reason_=Close::key_during_settle;closed_=true;return Step::closed;}return Step::starting;}
    return Step::active;
}
} // namespace minecome::hud::input
