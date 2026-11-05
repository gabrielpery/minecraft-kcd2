#include "stream_contract.hpp"
#include "input_contract.hpp"
#include "gameplay_keyboard_policy.hpp"
#include "movement_forwarding.hpp"
#include "selective_forwarding.hpp"
#include <cstring>
#include <iostream>
#include <stdexcept>

namespace st=minecome::hud::stream;
namespace ui=minecome::hud::input;
namespace {
unsigned checks=0;
void check(bool value,const char *label){++checks;if(!value)throw std::runtime_error(label);}
void put32(std::span<std::uint8_t> b,std::size_t at,std::uint32_t value){for(unsigned i=0;i<4;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8));}
void put64(std::span<std::uint8_t> b,std::size_t at,std::uint64_t value){for(unsigned i=0;i<8;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8));}
std::string arm(const st::Identity &id){
    return "[HudStream]\nSchema="+std::to_string(id.schema)+"\nRun="+id.run+"\nTargetPid=19\nTargetStart=200\nProducerPid=17\nProducerStart=100\nExpiresUtcMs="+std::to_string(id.expires_utc_ms)+"\n";
}
std::array<std::uint8_t,256> header(const st::Identity &id){
    std::array<std::uint8_t,256> b{};std::memcpy(b.data(),id.schema==3?"MCHUDS03":"MCHUDS01",8);
    put32(b,8,id.schema);put32(b,12,256);std::memcpy(b.data()+16,id.run.data(),32);
    put32(b,48,id.producer_pid);put32(b,52,id.target_pid);put64(b,56,id.producer_start);put64(b,64,id.target_start);put64(b,72,id.expires_utc_ms);
    put64(b,80,1);put64(b,88,100000);put32(b,96,2);put32(b,100,1);put32(b,104,8);put32(b,108,8);put32(b,112,1);put32(b,116,1);return b;
}
void stream_tests(){
    st::Identity id{"0123456789abcdef0123456789abcdef",17,19,100,200,100000+st::gameplay_max_lease_ms,3},parsed;
    std::string error;check(st::parse_arm(arm(id),19,200,100000,parsed,error,3)&&parsed.schema==3,"explicit gameplay arm");
    check(!st::parse_arm(arm(id),19,200,100000,parsed,error),"legacy addon rejects gameplay arm");
    auto legacy=id;legacy.schema=1;legacy.expires_utc_ms=120000;
    check(!st::parse_arm(arm(legacy),19,200,100000,parsed,error,3),"gameplay addon rejects legacy arm");
    check(st::parse_arm(arm(legacy),19,200,100000,parsed,error),"legacy arm still accepted");
    auto too_long=id;++too_long.expires_utc_ms;
    check(!st::parse_arm(arm(too_long),19,200,100000,parsed,error,3),"24 hour outer bound remains finite");
    auto invalid=id;invalid.schema=2;check(!st::valid_identity(invalid),"unknown stream profile rejected");
    st::Validator v;st::Header out;check(v.start(id,100000,5000),"gameplay session starts");
    auto b=header(id);check(v.accept(b,100000,5000,out)==st::Result::frame,"gameplay first frame");
    check(v.live(131000,36000)&&!v.fresh(131000,36000),"past 30s lifetime does not grant freshness");
    put64(b,80,2);put64(b,88,131000);
    check(v.accept(b,131000,36000,out)==st::Result::frame&&v.fresh(131000,36000),"fresh frame beyond old cutoff");
    check(v.fresh(131500,36500)&&!v.fresh(131501,36501),"unchanged 500ms frame lease");
    put32(b,116,2);check(v.accept(b,132000,37000,out)==st::Result::closed&&!v.live(132000,37000),"explicit producer stop terminal");
    check(!v.start(id,132000,37000),"stopped identity cannot restart");
    for(bool reverse:{false,true}){
        auto selected=reverse?legacy:id;st::Validator cross;check(cross.start(selected,100000,5000),"cross profile validator starts");
        auto wrong=header(reverse?id:legacy);check(cross.accept(wrong,100000,5000,out)==st::Result::invalid,"stream profiles cannot cross");
    }
    st::Validator expiry;check(expiry.start(id,100000,5000)&&!expiry.live(id.expires_utc_ms,5000+st::gameplay_max_lease_ms),"outer cap exact boundary");
}
void input_tests(){
    ui::KeyboardGate gate(true);
    check(gate.update(false,false,0,99)==ui::KeyboardGate::Step::idle,"ineligible cannot autostart");
    check(gate.update(true,false,1,100)==ui::KeyboardGate::Step::idle,"held control cannot autostart");
    check(gate.update(true,true,0,101)==ui::KeyboardGate::Step::idle,"held F8 cannot autostart");
    check(gate.update(true,false,0,102)==ui::KeyboardGate::Step::starting,"eligible released controls autostart");
    check(gate.update(true,false,0,103)==ui::KeyboardGate::Step::starting,"neutral settling first frame");
    check(gate.update(true,false,0,104)==ui::KeyboardGate::Step::starting,"neutral settling second frame");
    check(gate.update(true,false,1,105)==ui::KeyboardGate::Step::active,"later controls forwarded");
    check(gate.update(true,false,1,60105)==ui::KeyboardGate::Step::active,"gameplay persists beyond30s");
    check(gate.update(true,true,0,60106)==ui::KeyboardGate::Step::closed,"F8 explicitly stops gameplay");
    check(gate.update(true,false,0,60107)==ui::KeyboardGate::Step::closed,"stopped gate cannot autostart again");
    ui::KeyboardGate lost(true);lost.update(true,false,0,100);lost.update(true,false,0,101);lost.update(true,false,0,102);
    check(lost.update(false,false,0,103)==ui::KeyboardGate::Step::closed&&lost.close_reason()==ui::KeyboardGate::Close::ineligible,"peer or owner loss still closes");
    ui::KeyboardGate early(true);early.update(true,false,0,100);
    check(early.update(true,false,1,101)==ui::KeyboardGate::Step::closed,"settling control edge refuses takeover");
    ui::KeyboardGate legacy;legacy.update(true,false,0,100);legacy.update(true,true,0,101);
    check(legacy.update(true,false,0,30101)==ui::KeyboardGate::Step::closed&&legacy.close_reason()==ui::KeyboardGate::Close::expired,"legacy30s bound unchanged");
    const st::Identity id{"0123456789abcdef0123456789abcdef",17,19,100,200,100000+st::gameplay_max_lease_ms,3};
    std::array<std::uint8_t,128> encoded{};ui::encode_host(encoded,id,0,0,0,ui::Profile::gameplay);
    check(std::memcmp(encoded.data(),"MCHUDI03",8)==0&&encoded[8]==3,"explicit input v3 header");
    const ui::Event e{1000,ui::Kind::key_down,0x45};
    check(ui::valid_event(e,1250,ui::Profile::gameplay)&&!ui::valid_event(e,1251,ui::Profile::gameplay),"gameplay retains250ms input lease");
    const ui::Event walk{1000,ui::Kind::key_down,0x57};
    check(!ui::valid_event(walk,1000)&&ui::valid_event(walk,1000,ui::Profile::movement)&&!ui::valid_event(walk,1000,ui::Profile::gameplay),"movement is not part of the initial gameplay UI contract");
    ui::encode_host(encoded,id,0,0,0,ui::Profile::gameplay_movement);
    check(std::memcmp(encoded.data(),"MCHUDI04",8)==0&&encoded[8]==4,"explicit sustained movement header");
    for(auto code:ui::movement_keys){
        const ui::Event down{1000,ui::Kind::key_down,code},up{1000,ui::Kind::key_up,code};
        check(ui::valid_event(down,1250,ui::Profile::gameplay_movement)&&ui::valid_event(up,1250,ui::Profile::gameplay_movement),"sustained movement edges accepted");
        check(!ui::valid_event(down,1251,ui::Profile::gameplay_movement)&&!ui::valid_event(down,1000,ui::Profile::gameplay),"v4 age and v3 isolation retained");
    }
    check(ui::valid_event(e,1000,ui::Profile::gameplay_movement),"v4 retains ordinary UI events");
    check(!ui::valid_event({1000,ui::Kind::key_down,0x10},1000,ui::Profile::gameplay_movement),"unimplemented sprint or modifier not silently forwarded");
    ui::MovementGate movement;
    movement.update(true,0);movement.update(true,0);
    check(movement.update(true,1).down==1,"physical forward edge starts after neutral ownership");
    check(movement.update(false,1).up==1&&movement.held()==0,"inventory transition releases forward before UI toggle");
    movement.update(true,1);check(!movement.armed(),"held key cannot leak out of inventory");
    movement.update(true,0);movement.update(true,0);
    check(movement.update(true,1).down==1,"fresh press resumes after inventory neutral frames");
    namespace mouse=minecome::selective;
    mouse::ModeGate world_mouse;
    check(world_mouse.update(true,false,0,0,false,0,false)==mouse::Mode::full,"world mouse starts at neutral boundary");
    check(world_mouse.update(true,false,0,0,false,0,false)==mouse::Mode::buttons,"neutral world mode releases mouse ownership");
    check(world_mouse.update(true,false,0,0,false,1,true)==mouse::Mode::buttons,"native world click preserves mouse passthrough");
    check(world_mouse.update(true,true,0,0,true,0,true)==mouse::Mode::full,"UI toggle captures mouse before inventory");
    check(world_mouse.update(true,false,1,1,false,1,false)==mouse::Mode::full,"inventory owns dragging button");
    check(world_mouse.update(true,false,0,0,false,1,false)==mouse::Mode::full,"closing inventory retains held-button drain");
    check(world_mouse.update(true,false,0,0,false,0,false)==mouse::Mode::full,"inventory exit first neutral frame");
    check(world_mouse.update(true,false,0,0,false,0,false)==mouse::Mode::buttons,"inventory exit restores native mouse after neutral");
}
void keyboard_mask_tests(){
    namespace gk=minecome::gameplay_keyboard;
    gk::Policy p;
    check(!p.request(1,2,101,gk::Mode::ui,1000,true),"keyboard lease cannot exceed100ms");
    check(!p.request(1,2,100,gk::Mode::ui,1000,false),"keyboard requires foreground ownership");
    check(p.request(1,2,100,gk::Mode::ui,1000,true),"UI mask acquired");
    for(unsigned key='1';key<='9';++key)check(p.blocks(key,1000,true),"hotbar key suppressed for host");
    check(p.blocks('E',1000,true)&&p.blocks(0x1b,1000,true),"inventory toggles suppressed for host");
    for(unsigned key: std::array<unsigned,6>{'W','A','S','D',0x20,0x77})check(!p.blocks(key,1000,true),"native movement and stop key preserved outside inventory");
    check(!p.request(1,3,100,gk::Mode::full,1001,true),"foreign token cannot replace keyboard owner");
    check(!p.release(1,3)&&p.query(1,2,1002,true),"foreign release cannot end lease");
    check(p.blocks('E',1099,true)&&!p.blocks('E',1100,true),"keyboard freshness expires exactly100ms");
    check(!p.query(1,2,1100,true),"expired lease is not renewable proof");
    check(p.request(1,2,100,gk::Mode::full,1200,true)&&p.blocks('W',1201,true),"inventory captures movement");
    check(p.request(1,2,100,gk::Mode::ui,1202,true)&&!p.blocks('W',1203,true),"leaving inventory restores movement");
    check(!p.blocks('E',1204,false)&&!p.query(1,2,1205,true),"focus loss revokes lease irreversibly");
    check(p.request(1,2,100,gk::Mode::ui,1300,true)&&!p.blocks('E',1299,true),"clock regression revokes keyboard");
    check(p.request(1,2,100,gk::Mode::ui,1400,true)&&p.release(1,2)&&!p.blocks('E',1401,true),"explicit stop releases keys");
    check(gk::ui_scan(1)&&gk::ui_scan(2)&&gk::ui_scan(10)&&gk::ui_scan(0x12)&&!gk::ui_scan(0x11),"DirectInput scan mask matches UI keys only");
}
}
int main(){try{stream_tests();input_tests();keyboard_mask_tests();std::cout<<"HUD_GAMEPLAY_SESSION_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
