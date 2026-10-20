#include "movement_forwarding.hpp"
#include "input_contract.hpp"
#include <cstring>
#include <iostream>
#include <stdexcept>
namespace ui=minecome::hud::input;
namespace {
unsigned checks=0;
void check(bool okay,const char *why){++checks;if(!okay)throw std::runtime_error(why);}
void neutral(ui::MovementGate &gate){
    check(!gate.update(true,0).down&&!gate.armed(),"first neutral frame suppresses");
    check(!gate.update(true,0).down&&gate.armed(),"second neutral frame arms");
}
void contract(){
    for(unsigned key=0;key<256;++key){
        const bool old=(key>=0x31&&key<=0x39)||key==0x45||key==0x1b;
        const bool movement=key==0x57||key==0x41||key==0x53||key==0x44||key==0x20;
        check(ui::valid_key(key)==old,"v1 whitelist unchanged");
        check(ui::valid_key(key,ui::Profile::movement)==(old||movement),"v2 whitelist exact");
        for(auto kind:{ui::Kind::key_down,ui::Kind::key_up}){
            check(ui::valid_event({1000,kind,key},1000)==old,"v1 event whitelist unchanged");
            check(ui::valid_event({1000,kind,key},1000,ui::Profile::movement)==(old||movement),"v2 event whitelist exact");
        }
    }
    for(auto key:ui::movement_keys){
        check(ui::valid_event({750,ui::Kind::key_down,key},1000,ui::Profile::movement),"v2 exact250ms bound");
        check(!ui::valid_event({749,ui::Kind::key_down,key},1000,ui::Profile::movement),"v2 no age extension");
        check(!ui::valid_event({1101,ui::Kind::key_up,key},1000,ui::Profile::movement),"v2 future bound");
        check(!ui::valid_event({1000,ui::Kind::key_down,key,.1f},1000,ui::Profile::movement),"v2 no coordinate payload");
    }
    check(!ui::valid_event({1000,ui::Kind::move,0},1000,static_cast<ui::Profile>(3)),"unknown profile fails");
    const ui::Identity id{"0123456789abcdef0123456789abcdef",2,3,4,5,10000};
    std::array<std::uint8_t,128> old{},movement{};
    ui::encode_host(old,id,8,1000,1);ui::encode_host(movement,id,8,1000,1,ui::Profile::movement);
    check(!std::memcmp(old.data(),"MCHUDI01",8)&&old[8]==1,"v1 original magic/version");
    check(!std::memcmp(movement.data(),"MCHUDI02",8)&&movement[8]==2,"v2 explicit magic/version");
    for(unsigned i=0;i<old.size();++i)if(i!=7&&i!=8)check(old[i]==movement[i],"all identity/reserved/ring layout bytes unchanged");
}
void gate(){
    // All held combinations, not just a single convenient forward key.
    for(std::uint32_t mask=1;mask<32;++mask){
        ui::MovementGate gate;
        check(!gate.update(true,mask).down&&!gate.armed(),"already held movement cannot activate");
        neutral(gate);
        auto first=gate.update(true,mask);
        check(first.down==mask&&first.up==0&&gate.held()==mask,"fresh physical press exactly forwarded");
        auto repeat=gate.update(true,mask);
        check(!repeat.down&&!repeat.up,"held key does not fabricate repeat edge");
        auto release=gate.update(false,mask);
        check(release.up==mask&&!release.down&&!gate.held()&&!gate.armed(),"inventory transition or ownership uncertainty releases all before UI");
        check(!gate.update(false,0).up,"unavailable repeats cannot duplicate release");
        for(unsigned i=0;i<3;++i)check(!gate.update(true,mask).down&&!gate.armed(),"held across inventory close cannot resume");
        neutral(gate);
        check(gate.update(true,mask).down==mask,"fresh press after neutral resumes");
        auto up=gate.update(true,0);check(up.up==mask&&!up.down,"physical keyup releases");
        check(!gate.update(true,0).up,"physical up not repeated");
    }
    ui::MovementGate chord;neutral(chord);chord.update(true,1|16);
    auto changed=chord.update(true,2|16);
    check(changed.up==1&&changed.down==2&&chord.held()==(2|16),"diagonal/jump chord tracks individual edges");
    ui::MovementGate early;
    early.update(true,0);early.update(true,1);early.update(true,0);
    check(!early.armed(),"nonneutral frame resets two-frame rearm");
    early.update(true,0);check(early.armed(),"two consecutive neutral frames required");
    // The production F8 latch receives all16 bits, including the5 movement keys.
    for(unsigned index=11;index<16;++index){
        ui::KeyboardGate latch;
        latch.update(true,false,0,100);
        check(latch.update(true,true,1u<<index,101)==ui::KeyboardGate::Step::idle,"held WASD/Space prevents F8 activation");
        latch.update(true,false,0,102);check(latch.update(true,true,0,103)==ui::KeyboardGate::Step::starting,"fresh F8 after neutral can activate");
        check(latch.update(true,false,1u<<index,104)==ui::KeyboardGate::Step::closed,"WASD/Space during ownership settling fails closed");
    }
}
}
int main(){try{contract();gate();std::cout<<"HUD_MOVEMENT_TESTS checks="<<checks<<" PASS\n";return 0;}
catch(const std::exception &e){std::cerr<<"HUD_MOVEMENT_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
