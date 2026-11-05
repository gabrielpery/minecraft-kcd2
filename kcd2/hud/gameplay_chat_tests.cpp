#include "gameplay_chat.hpp"
#include "movement_forwarding.hpp"
#include "gameplay_world_buttons.hpp"
#include "selective_forwarding.hpp"
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace ui=minecome::hud::input;
namespace {
unsigned checks=0;
void check(bool value,const char *label){++checks;if(!value)throw std::runtime_error(label);}
void put32(std::span<std::uint8_t> b,std::size_t at,std::uint32_t value){for(unsigned i=0;i<4;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8));}
void put64(std::span<std::uint8_t> b,std::size_t at,std::uint64_t value){for(unsigned i=0;i<8;++i)b[at+i]=static_cast<std::uint8_t>(value>>(i*8));}
void contract(){
    constexpr auto profile=ui::Profile::gameplay_chat;
    for(unsigned i=1;i<=5;++i){
        const auto old=static_cast<ui::Profile>(i);
        check(!ui::valid_event({1000,ui::Kind::text,'a'},1000,old),"old profile rejects text");
        check(!ui::valid_event({1000,ui::Kind::edit_down,8},1000,old),"old profile rejects edits");
        check(!ui::valid_key('T',old)&&!ui::valid_key(0xbf,old),"old opener allowlists remain frozen");
        check(!ui::valid_key(0x10,old)&&!ui::valid_key(0x11,old),"old flight modifier allowlists remain frozen");
    }
    check(ui::valid_key('T',profile)&&ui::valid_key(0xbf,profile),"explicit chat openers");
    check(ui::valid_key(0x10,profile)&&ui::valid_key(0x11,profile),"input6 flight modifiers");
    for(auto key:ui::movement_keys)check(ui::valid_key(key,profile),"chat retains physical movement");
    for(auto kind:{ui::Kind::world_button_down,ui::Kind::world_button_up})check(ui::valid_event({1000,kind,1},1000,profile),"chat retains world actions");
    for(unsigned scalar:{32u,126u,160u,0x263au,0x10000u,0x1f600u,0x10ffffu})check(ui::valid_event({1000,ui::Kind::text,scalar},1000,profile),"valid Unicode scalar");
    for(unsigned scalar:{0u,31u,127u,159u,0xd800u,0xdbffu,0xdc00u,0xdfffu,0x110000u,0xffffffffu})check(!ui::valid_event({1000,ui::Kind::text,scalar},1000,profile),"reject controls and malformed scalar");
    check(!ui::valid_event({1000,ui::Kind::text,'a',.1f,0,0},1000,profile),"text coordinates prohibited");
    check(!ui::valid_event({1000,ui::Kind::text,'a',0,0,1},1000,profile),"text modifiers prohibited");
    check(!ui::valid_event({1000,ui::Kind::text,'a'},1251,profile),"stale text rejected");
    for(unsigned key=0;key<256;++key){
        const bool allowed=key==8||key==9||key==13||key==27||(key>=35&&key<=40)||key==46;
        check(ui::valid_event({1000,ui::Kind::edit_down,key},1000,profile)==allowed,"edit allowlist");
        check(ui::valid_event({1000,ui::Kind::edit_up,key},1000,profile)==allowed,"edit release allowlist");
    }
    ui::Identity id{"0123456789abcdef0123456789abcdef",17,19,100,200,110000,3};
    std::array<std::uint8_t,128> host{};ui::encode_host(host,id,0,1000,1,profile);
    check(std::memcmp(host.data(),"MCHUDI06",8)==0&&host[8]==6,"new input identity");
    std::array<std::uint8_t,128> bytes{};put64(bytes,0,1);put64(bytes,8,1000);put32(bytes,16,1);put32(bytes,20,2);
    ui::Ack ack;std::string reason;
    check(ui::decode_ack(bytes,1,1000,{},ack,reason,true,profile)&&ack.screen==2,"chat ACK accepted only by profile6");
    check(!ui::decode_ack(bytes,1,1000,{},ack,reason),"old ACK parser rejects chat screen");
    put32(bytes,20,3);check(!ui::decode_ack(bytes,1,1000,{},ack,reason,true,profile),"unknown screen rejected");
    put32(bytes,20,2);bytes[30]=1;check(!ui::decode_ack(bytes,1,1000,{},ack,reason,true,profile),"reserved chat ACK rejected");
    check(ui::chat_render_screen(2)==1&&ui::chat_render_screen(0)==0&&ui::chat_render_screen(1)==1,"chat uses frozen UI rendering screen");
}
void keyboard(){
    ui::ChatKeyboard keyboard;ui::ChatKeyState keys{};
    keys['T']=0x80;keyboard.update(false,keys,1000);
    check(!keyboard.update(true,keys,1001).down['T'],"held opener not typed on entry");
    check(!keyboard.update(true,keys,1600).down['T'],"opener cannot become repeat");
    keys['T']=0;keyboard.update(true,keys,1601);keys['T']=0x80;
    check(keyboard.update(true,keys,1602).down['T'],"new text edge after release");
    check(!keyboard.update(true,keys,2001).down['T'],"repeat waits400ms");
    check(keyboard.update(true,keys,2002).down['T'],"text repeats at400ms");
    check(!keyboard.update(true,keys,2051).down['T']&&keyboard.update(true,keys,2052).down['T'],"repeat50ms cadence");
    check(keyboard.update(true,keys,6000).down['T']&&!keyboard.update(true,keys,6000).down['T'],"stall generates no repeat backlog");
    keys={};keyboard.update(true,keys,6001);keys[8]=0x80;
    check(keyboard.update(true,keys,6002).down[8]&&keyboard.update(true,keys,6402).down[8],"backspace supports repeat");keyboard.forwarded_edit(8);
    check(keyboard.update(false,keys,6403).up[8],"screen or lease loss releases editor");
    check(!keyboard.update(true,keys,7000).down[8],"held edit not replayed after recovery");
    keys={};keyboard.update(true,keys,7001);keys[13]=0x80;
    check(keyboard.update(true,keys,7002).down[13]&&!keyboard.update(true,keys,8000).down[13],"Enter never repeats");
    keys[46]=0x80;check(keyboard.update(true,keys,8001).down[46],"simultaneous closing batch may sample another editor key");
    check(!keyboard.update(false,keys,8002).up[46],"unsent edit never acquires a release");
    keys={};keyboard.update(false,keys,8001);keys[0x11]=0x80;keys['V']=0x80;
    check(!keyboard.update(true,keys,8002).down['V'],"Ctrl chord not forwarded");
    keys[0x11]=0;check(!keyboard.update(true,keys,8500).down['V'],"modifier release cannot replay chord");
    keys={};keyboard.update(true,keys,8501);keys[0xa5]=0x80;keys['Q']=0x80;
    check(!keyboard.update(true,keys,8502).down['Q'],"AltGr chord not forwarded");
    keys={};keyboard.update(false,keys,8503);keys['W']=0x80;keyboard.update(false,keys,8504);
    check(!keyboard.update(true,keys,9000).down['W'],"key pressed during transition not replayed");
}
void unicode(){
    std::vector<std::uint32_t> out;
    const std::array<std::uint16_t,9> input{'A',0xd83d,0xde00,0xd800,'B',0xdc00,0x7f,0x1f,0xe9};
    check(ui::chat_utf16(input,[&](auto scalar){out.push_back(scalar);return true;}),"UTF16 conversion succeeds");
    check(out==std::vector<std::uint32_t>{'A',0x1f600,'B',0xe9},"UTF16 scalar decoding filters controls and isolated surrogates");
    check(!ui::chat_utf16(input,[](auto){return false;}),"bounded sink failure propagates");
}
void released_taps(){
    ui::ReleasedTapGate gate;ui::ChatKeyboard keyboard;ui::ChatKeyState down{},released{};
    check(!gate.update(true,down,released)['T'],"first sample only establishes baseline");
    for(unsigned key:{static_cast<unsigned>('T'),0xbfu,static_cast<unsigned>('2'),static_cast<unsigned>('A'),8u,13u,27u}){
        released={};gate.update(true,down,released);released[key]=1;
        auto taps=gate.update(true,down,released);
        check(taps[key]!=0,"fresh release between up samples recovers one short tap");
        check(!gate.update(true,down,released)[key],"same release observation cannot replay");
        keyboard.update(true,down,1000);
        const auto event=keyboard.update(true,down,1001,taps);
        check(event.down[key]&&event.pulse[key]&&!event.up[key],"tap is explicit one-shot down requiring immediate paired edit up");
        check(!keyboard.update(true,down,2000).down[key],"tap arms no held repeat");
        check(!keyboard.update(false,down,2001).up[key],"paired pulse leaves no editor release debt");
    }
    released={};gate.update(true,down,released);down['A']=0x80;
    check(!gate.update(true,down,released)['A'],"ordinary held edge is not a tap");
    down['A']=0;released['A']=1;
    check(!gate.update(true,down,released)['A'],"normal held release cannot duplicate a character");
    released={};gate.update(true,down,released);released['A']=1;
    check(!gate.update(false,down,released)['A'],"transition consumes short tap without dispatch");
    check(!gate.update(true,down,released)['A'],"transition tap cannot replay after reopening");
    released={};gate.update(true,down,released);released['A']=1;
    check(gate.update(true,down,released)['A']!=0,"later distinct tap works after recovery");
    for(unsigned modifier:{0x10u,0x11u,0x12u,0xa0u,0xa1u,0xa2u,0xa3u,0xa4u,0xa5u}){
        down={};released={};gate.update(true,down,released);gate.update(true,down,released);
        released[modifier]=released['V']=1;
        check(!gate.update(true,down,released)['V'],"vanished modifier chord cannot become a plain text tap");
        released={};released['V']=1;
        check(!gate.update(true,down,released)['V'],"modifier uncertainty requires a new clean observation");
    }
    down={};released={};gate.update(true,down,released);gate.update(true,down,released);
    down['W']=0x80;gate.update(false,down,released);down['W']=0;released['W']=1;
    check(!gate.update(true,down,released)['W'],"held release across disabled interval never becomes a pulse");
}
void ownership(){
    ui::MovementGate movement;ui::GameplayWorldButtons world;
    movement.update(true,0);movement.update(true,0);world.update(true,0,1000);world.update(true,0,1001);
    check(movement.update(true,1).down==1,"world movement begins");
    check(world.update(true,1,1002).count==1,"world action begins");
    check(movement.update(false,1).up==1,"chat transition releases movement");
    const auto release=world.update(false,1,1003);
    check(release.count==1&&release.events[0].kind==ui::Kind::world_button_up,"chat transition releases mining");
    check(movement.update(true,1).down==0&&world.update(true,1,1004).count==0,"held controls cannot leak out of chat");
    minecome::selective::ModeGate mode;
    check(mode.update(true,false,2,1,false,0,true)==minecome::selective::Mode::full,"chat requires full mouse capture");
    check(mode.update(true,true,0,1,false,0,true)==minecome::selective::Mode::full,"closing chat retains full capture until pixels agree");
}
void flight_movement(){
    for(std::uint32_t mask=1;mask<128;++mask){
        ui::MovementGate gate{127u};
        check(!gate.update(true,mask).down&&!gate.armed(),"flight keys already held cannot acquire ownership");
        gate.update(true,0);gate.update(true,0);
        auto press=gate.update(true,mask);
        check(press.down==mask&&!press.up&&!press.pulse,"all flight chord combinations forward once");
        auto still=gate.update(true,mask);check(!still.down&&!still.up&&!still.pulse,"flight hold never fabricates repeats");
        auto lost=gate.update(false,mask,16);check(lost.up==mask&&!lost.down&&!lost.pulse,"UI or lease loss releases modifiers and drops jump pulse");
        check(!gate.update(true,mask).down&&!gate.armed(),"flight held across UI must release before reuse");
        gate.update(true,0);gate.update(true,0);
        check(gate.update(true,mask).down==mask,"flight controls resume after neutral");
    }
    ui::MovementGate pulse{127u};
    check(!pulse.update(true,0,16).pulse&&!pulse.armed(),"jump pulse suppressed before ownership");
    pulse.update(true,0);
    auto first=pulse.update(true,0,16);
    check(first.pulse==16&&!first.down&&!first.up&&!pulse.held(),"short jump yields one balanced pulse without held debt");
    check(!pulse.update(true,0).pulse,"jump pulse does not repeat in next sample");
    check(pulse.update(true,0,16).pulse==16,"second distinct jump pulse reaches vanilla double tap queue");
    auto held=pulse.update(true,16,16);check(held.down==16&&!held.pulse,"held jump and release pulse cannot duplicate");
    auto release=pulse.update(true,0,16);check(release.up==16&&!release.pulse,"held release cannot become second jump tap");
    check(!pulse.update(false,0,16).pulse,"jump pulse cannot cross screen transition");
    check(!pulse.update(true,0,16).pulse,"jump pulse cannot replay while ownership rearms");
    ui::MovementGate legacy;legacy.update(true,0);legacy.update(true,0);
    check(!legacy.update(true,96).down&&!legacy.held(),"legacy gate still masks flight modifiers");
}
}
int main(){try{contract();keyboard();unicode();released_taps();ownership();flight_movement();std::cout<<"HUD_GAMEPLAY_CHAT_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
