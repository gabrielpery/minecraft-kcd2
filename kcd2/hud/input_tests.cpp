#include "input_channel.hpp"
#include "input_json.hpp"
#include <bit>
#include <cstring>
#include <iostream>
#include <limits>
#include <sstream>
#include <thread>
namespace ui=minecome::hud::input;
namespace st=minecome::hud::stream;
namespace {
unsigned checks=0;
void check(bool value,const char *message) {++checks;if(!value)throw std::runtime_error(message);}
void put32(std::span<std::uint8_t> b,std::size_t o,std::uint32_t n){for(unsigned i=0;i<4;++i)b[o+i]=static_cast<std::uint8_t>(n>>(i*8));}
void put64(std::span<std::uint8_t> b,std::size_t o,std::uint64_t n){for(unsigned i=0;i<8;++i)b[o+i]=static_cast<std::uint8_t>(n>>(i*8));}
std::array<std::uint8_t,128> ack(std::uint64_t sequence,std::uint64_t utc,std::uint32_t state=1) {
    std::array<std::uint8_t,128> bytes{};put64(bytes,0,sequence);put64(bytes,8,utc);put32(bytes,16,state);return bytes;
}
void contract() {
    check(ui::fresh(750,1000)&&ui::fresh(1100,1000),"freshness boundaries");
    check(!ui::fresh(749,1000)&&!ui::fresh(1101,1000)&&!ui::fresh(0,0),"stale future or zero");
    for(auto key:{0x31u,0x32u,0x39u,0x45u,0x1bu})check(ui::valid_event({1000,ui::Kind::key_down,key},1000),"allowed key");
    for(auto key:{0u,0x30u,0x3au,0x46u,0x77u})check(!ui::valid_event({1000,ui::Kind::key_down,key},1000),"unknown key rejected");
    check(!ui::valid_event({1000,ui::Kind::key_down,0x31,.5f,0},1000),"key coordinates zero");
    for(auto bad:{-1.0f,1.1f,std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()})
        check(!ui::valid_event({1000,ui::Kind::move,0,bad,0},1000),"coordinate malformed");
    check(ui::valid_event({1000,ui::Kind::button_down,1,1,1},1000),"right button valid");
    check(!ui::valid_event({1000,ui::Kind::button_down,2,0,0},1000),"invalid button");
    check(ui::valid_event({1000,ui::Kind::wheel,0,.2f,.5f,-16},1000),"wheel valid");
    check(!ui::valid_event({1000,ui::Kind::wheel,0,.2f,.5f,0},1000),"wheel zero rejected");
    check(!ui::valid_event({1000,static_cast<ui::Kind>(7),0},1000),"event kind unknown");
    ui::Ack previous{},parsed;std::string reason;
    auto bytes=ack(0,1000);
    check(ui::decode_ack(bytes,0,1000,previous,parsed,reason),"initial ready");previous=parsed;
    check(ui::decode_ack(bytes,0,1100,previous,parsed,reason),"duplicate ack fresh");
    check(!ui::decode_ack(bytes,0,1251,previous,parsed,reason),"duplicate ack expires");
    check(ui::decode_ack(bytes,0,1251,previous,parsed,reason,false)&&!ui::fresh(parsed.utc,1251),"old waiting ACK parses without readiness");
    auto fresh_recovery=ack(0,1251);
    check(ui::decode_ack(fresh_recovery,0,1251,previous,parsed,reason,false)&&ui::fresh(parsed.utc,1251),"new real client tick restores readiness");
    auto zero_time=ack(0,0);
    check(!ui::decode_ack(zero_time,0,1000,previous,parsed,reason,false)&&reason=="ack_timestamp_zero","waiting zero time fatal");
    auto future_time=ack(0,1101);
    check(!ui::decode_ack(future_time,0,1000,previous,parsed,reason,false)&&reason=="ack_future","waiting future time fatal");
    auto regressed_time=ack(0,999);
    check(!ui::decode_ack(regressed_time,0,1000,previous,parsed,reason,false)&&reason=="ack_time_regressed","waiting time regression fatal");
    check(!ui::decode_ack(bytes,0,1251,previous,parsed,reason,true)&&reason=="ack_aged","armed old ACK remains fatal");
    auto future=ack(1,1000);check(!ui::decode_ack(future,0,1000,previous,parsed,reason),"ack past event head rejected");
    auto waiting=ack(0,0,0);check(!ui::decode_ack(waiting,0,1000,previous,parsed,reason),"ready cannot regress waiting");
    auto closed=ack(0,1000,2);check(ui::decode_ack(closed,0,1000,previous,parsed,reason),"closed ack");
    for(auto offset:{28u,127u}){auto reserved=bytes;reserved[offset]=1;check(!ui::decode_ack(reserved,0,1000,previous,parsed,reason),"reserved ack rejected");}
    ui::Mailbox mailbox;ui::Event event{1000,ui::Kind::key_down,0x31},out;
    check(!mailbox.pop(out),"empty mailbox");
    for(unsigned i=0;i<64;++i){event.code=i;check(mailbox.push(event),"bounded mailbox write");}
    check(!mailbox.push(event)&&mailbox.overflowed(),"mailbox overflow terminal marker");
    for(unsigned i=0;i<64;++i)check(mailbox.pop(out)&&out.code==i,"mailbox exact order");
    check(!mailbox.pop(out),"mailbox drained");
    ui::KeyboardGate gate;
    check(gate.update(true,true,0,100)==ui::KeyboardGate::Step::idle,"held F8 without neutral cannot arm");
    check(gate.update(true,false,0,101)==ui::KeyboardGate::Step::idle,"neutral baseline");
    check(gate.update(true,true,0,102)==ui::KeyboardGate::Step::starting,"fresh F8 arms");
    check(gate.update(true,false,0,103)==ui::KeyboardGate::Step::starting,"settle frame1");
    check(gate.update(true,false,0,104)==ui::KeyboardGate::Step::starting,"settle frame2");
    check(gate.update(true,false,1,105)==ui::KeyboardGate::Step::active,"later UI key accepted");
    check(gate.update(false,false,0,106)==ui::KeyboardGate::Step::closed,"focus or fresh gate closes");
    check(gate.update(true,true,0,107)==ui::KeyboardGate::Step::closed,"no rearm");
    ui::KeyboardGate bounded;bounded.update(true,false,0,100);bounded.update(true,true,0,101);
    check(bounded.update(true,false,0,30101)==ui::KeyboardGate::Step::closed,"30second bound");
    ui::KeyboardGate early;early.update(true,false,0,100);early.update(true,true,0,101);
    check(early.update(true,false,1,102)==ui::KeyboardGate::Step::closed,"early keys during settling close");
    const auto j=ui::json::Parser("{\"value\":\"134999999999999999\",\"array\":[true,0.25],\"escaped\":\"C:\\\\x\"}").parse();
    check(j.at("value").integer()==134999999999999999ULL&&j.at("array").array[0].boolean()&&j.at("array").array[1].real()==.25f,"bounded JSON precise receipt");
    for(const auto text:{"{\"x\":1,\"x\":2}","{\"x\":01}","[1,]","{\"x\":NaN}","{} trailing","\"\\ud800\""}) {
        bool rejected=false;try{ui::json::Parser(text).parse();}catch(...){rejected=true;}check(rejected,"malformed JSON");
    }
}
ui::Identity identity(unsigned serial) {
    std::ostringstream run;run<<std::hex;run.width(16);run.fill('0');run<<GetCurrentProcessId();run.width(16);run<<st::steady_ms()+serial;
    return {run.str(),GetCurrentProcessId(),GetCurrentProcessId(),st::process_start(),st::process_start(),st::utc_ms()+10000};
}
struct Guest {
    st::Handle mapping,mutex;std::uint8_t *bytes=nullptr;
    explicit Guest(const ui::Identity &id) {
        const std::wstring token(id.run.begin(),id.run.end());mapping.reset(OpenFileMappingW(FILE_MAP_READ|FILE_MAP_WRITE,FALSE,(L"Local\\MineComeHudInput_"+token).c_str()));
        mutex.reset(OpenMutexW(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,(L"Local\\MineComeHudInputLock_"+token).c_str()));
        bytes=static_cast<std::uint8_t *>(MapViewOfFile(mapping.value,FILE_MAP_READ|FILE_MAP_WRITE,0,0,ui::mapping_bytes));check(mapping&&mutex&&bytes,"fixture guest open");
    }
    ~Guest(){if(bytes)UnmapViewOfFile(bytes);}
    void write(std::uint64_t sequence,std::uint32_t state=1) {
        auto header=ack(sequence,st::utc_ms(),state);check(WaitForSingleObject(mutex.value,5)==WAIT_OBJECT_0,"guest lock");
        std::memcpy(bytes+128,header.data(),128);check(ReleaseMutex(mutex.value)!=FALSE,"guest unlock");
    }
};
void channels() {
    auto id=identity(1);ui::Writer writer;check(writer.create(id),"writer new objects");Guest guest(id);
    check(!writer.ready()&&writer.poll(),"initial waiting permitted");guest.write(0);check(writer.poll()&&writer.ready(),"client ready acknowledged");
    ui::Writer collision;check(!collision.create(id),"existing mapping refused");
    check(writer.arm()&&writer.status().state==1,"one arm");check(!writer.arm(),"cannot rearm");
    ui::Event e{st::utc_ms(),ui::Kind::key_down,0x31};check(writer.append(std::span<const ui::Event>(&e,1)),"event published");
    check(writer.status().sequence==1&&guest.bytes[256]==1&&guest.bytes[128]==0,"host preserves guest-owned ack");
    guest.write(1);check(writer.poll()&&writer.status().ack.sequence==1,"client event ack");
    writer.finish("test_complete");check(guest.bytes[96]==2,"closed publication");guest.write(1,2);check(writer.poll()&&writer.status().ack.state==2,"guest close ack read");
    check(!writer.create(id),"cannot reopen");
    auto overflow_id=identity(2);ui::Writer full;check(full.create(overflow_id),"overflow fixture");Guest stalled(overflow_id);stalled.write(0);full.poll();full.arm();
    std::array<ui::Event,64> events;events.fill({st::utc_ms(),ui::Kind::key_down,0x31});check(full.append(events),"ring fills without overwrite");
    e.captured=st::utc_ms();check(!full.append(std::span<const ui::Event>(&e,1))&&full.status().state==2&&full.reason()=="ring_overflow","unacked overwrite closes");
    auto bad_id=identity(3);ui::Writer bad;check(bad.create(bad_id),"tamper fixture");Guest tamper(bad_id);tamper.write(0);bad.poll();
    WaitForSingleObject(tamper.mutex.value,5);tamper.bytes[16]^=1;ReleaseMutex(tamper.mutex.value);
    check(!bad.poll()&&bad.status().state==2&&bad.reason()=="host_bytes_changed","foreign header closes");
    auto abandoned_id=identity(4);ui::Writer abandoned;check(abandoned.create(abandoned_id),"abandoned fixture");Guest abandon(abandoned_id);
    std::thread quitter([&]{WaitForSingleObject(abandon.mutex.value,INFINITE);});quitter.join();
    check(!abandoned.poll()&&abandoned.reason()=="mutex_abandoned","abandon closes");
    auto stale_id=identity(5);ui::Writer stale;check(stale.create(stale_id),"stale fixture");Guest lag(stale_id);lag.write(0);stale.poll();stale.arm();
    WaitForSingleObject(lag.mutex.value,5);auto old=ack(0,st::utc_ms()-251);std::memcpy(lag.bytes+128,old.data(),128);ReleaseMutex(lag.mutex.value);
    check(!stale.poll()&&stale.status().state==2&&stale.reason()=="ack_time_regressed","regressed tick closes");
    auto recovery_id=identity(6);ui::Writer recovery;check(recovery.create(recovery_id),"waiting recovery fixture");Guest recovery_peer(recovery_id);
    recovery_peer.write(0);check(recovery.poll()&&recovery.ready(),"waiting real initial ACK");
    Sleep(270);check(recovery.poll()&&!recovery.ready()&&recovery.status().state==0,"waiting old ACK suspends readiness only");
    check(!recovery.arm()&&recovery.status().state==0,"cannot arm on stale waiting ACK");
    check(recovery.status().max_prearm_ack_age_ms>250&&recovery.status().prearm_stale_observations>0,"waiting diagnostic records actual age");
    recovery_peer.write(0);check(recovery.poll()&&recovery.ready()&&recovery.status().prearm_recoveries==1,"real fresh ACK recovers waiting session");
    check(recovery.arm(),"arm after real recovery");Sleep(270);
    check(!recovery.poll()&&recovery.status().state==2&&recovery.reason()=="ack_aged","active ACK lapse remains terminal");
    check(recovery.status().rejected_host_state==1&&recovery.status().rejected_at_utc_ms-recovery.status().rejected_ack_utc_ms>250,"rejection records exact active ACK age");
    recovery_peer.write(0);recovery.poll();check(!recovery.ready()&&!recovery.arm(),"fresh ACK never rearms closed ownership");
    Sleep(270);check(recovery.poll()&&recovery.status().state==2,"closed rendezvous may await delayed ACK without ownership");
    recovery_peer.write(0,2);check(recovery.poll()&&recovery.status().ack.state==2,"delayed real closed acknowledgement observed");
}
}
int main() {try{contract();channels();std::cout<<"HUD_INPUT_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception&e){std::cerr<<"HUD_INPUT_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
