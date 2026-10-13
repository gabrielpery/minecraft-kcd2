#define NOKEYSTATES
#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include "../reshade/raw_motion_capture_adapter.hpp"
#include <iostream>
#include <stdexcept>
namespace r=minecome::raw_motion;
namespace a=r::adapter;
namespace {
unsigned checks=0;
void check(bool value,const char *why){++checks;if(!value)throw std::runtime_error(why);}
MSG message(){MSG value{};value.hwnd=reinterpret_cast<HWND>(7);value.message=WM_INPUT;value.wParam=RIM_INPUT;value.lParam=123;return value;}
RAWINPUT packet(){RAWINPUT value{};value.header.dwType=RIM_TYPEMOUSE;value.header.dwSize=sizeof(RAWINPUTHEADER)+sizeof(RAWMOUSE);value.header.hDevice=reinterpret_cast<HANDLE>(9);value.header.wParam=RIM_INPUT;value.data.mouse.lLastX=12;value.data.mouse.lLastY=-8;return value;}
void registration_tests(){
    r::Registration registration;
    check(!registration.matches(0)&&!registration.matches(7),"no implicit helper before successful registration");
    registration.observe(false,1,2,0,7);check(!registration.matches(7),"failed mouse registration cannot create witness");
    registration.observe(true,1,6,0,7);check(!registration.matches(7),"keyboard registration cannot authorize mouse helper");
    registration.observe(true,2,2,0,7);check(!registration.matches(7),"another usage page cannot authorize helper");
    registration.observe(true,1,2,0,7);check(registration.matches(7),"successful explicit mouse route recorded");
    registration.observe(false,1,2,0,8);check(registration.matches(7)&&!registration.matches(8),"failed replacement preserves actual route");
    registration.observe(false,1,2,RIDEV_REMOVE,0);check(registration.matches(7),"failed removal preserves actual route");
    registration.observe(true,1,6,RIDEV_REMOVE,0);check(registration.matches(7),"keyboard removal cannot change mouse route");
    registration.observe(true,1,2,0,8);check(!registration.matches(7)&&registration.matches(8),"successful replacement invalidates previous helper");
    registration.observe(true,1,2,RIDEV_REMOVE,0);check(!registration.matches(8)&&!registration.matches(0),"successful removal revokes helper");
    registration.observe(true,1,2,0,7);registration.observe(true,1,2,0,0);check(!registration.matches(7),"implicit foreground registration revokes helper witness");
    registration.observe(true,1,2,RIDEV_INPUTSINK,7);check(registration.matches(7),"registration flags do not broaden per-packet foreground restrictions");
    registration.observe(true,1,2,RIDEV_NOLEGACY,7);check(registration.matches(7),"NOLEGACY overlapping page flag bits retain explicit mouse target");
    registration.observe(true,1,2,RIDEV_EXCLUDE,7);check(!registration.matches(7),"mouse exclusion revokes helper witness");
    registration.observe(true,1,2,0,7);registration.observe(true,1,0,RIDEV_PAGEONLY,8);check(!registration.matches(7)&&!registration.matches(8),"page-wide registration cannot retain or invent explicit mouse route");
    registration.observe(true,1,2,0,7);registration.observe(true,1,2,0x80000000u,7);check(!registration.matches(7),"unknown registration mode revokes witness");
}
void policy_tests(){
    auto msg=message();auto raw=packet();
    const auto pristine_message=msg;const auto pristine_packet=raw;
    check(r::routed_message(msg,raw,sizeof(raw),11,true,true),"registered same-process helper pure motion admitted for resolved owner");
    check(std::memcmp(&msg,&pristine_message,sizeof(msg))==0&&std::memcmp(&raw,&pristine_packet,sizeof(raw))==0,"original message and raw packet remain immutable");
    check(!r::routed_message(msg,raw,sizeof(raw),11,false,true),"unregistered helper denied");
    check(!r::routed_message(msg,raw,sizeof(raw),11,true,false),"foreign helper denied");
    check(!r::routed_message(msg,raw,sizeof(raw),0,true,true),"unresolved owner denied");
    check(!r::routed_message(msg,raw,sizeof(raw),7,true,true),"main-window packets retain frozen R2 path");
    msg.hwnd=nullptr;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"null helper denied");msg=message();
    for(const auto kind:{WM_MOUSEMOVE,WM_LBUTTONDOWN,WM_RBUTTONUP,WM_MOUSEWHEEL,WM_KEYDOWN,WM_NULL}){
        msg.message=kind;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"nonraw message cannot use helper exception");
    }
    msg=message();msg.wParam=RIM_INPUTSINK;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"sink message blocked even for registered helper");
    msg.wParam=0x10000;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"unknown foreground code bits blocked");msg=message();
    raw.header.wParam=RIM_INPUTSINK;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"sink raw header blocked");raw=packet();
    raw.header.hDevice=nullptr;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"unattributed packet blocked");raw=packet();
    raw.header.dwType=RIM_TYPEKEYBOARD;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"keyboard packet blocked");raw=packet();
    raw.header.dwSize++;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"malformed size blocked");raw=packet();
    check(!r::routed_message(msg,raw,sizeof(RAWINPUTHEADER)-1,11,true,true),"truncated header blocked");
    check(!r::routed_message(msg,raw,raw.header.dwSize-1,11,true,true),"truncated body blocked");
    raw.data.mouse.lLastX=raw.data.mouse.lLastY=0;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"empty movement cannot bypass block");
    for(unsigned bit=1;bit<=0x8000;bit<<=1){
        raw=packet();raw.data.mouse.usFlags=static_cast<USHORT>(bit);
        check(r::routed_message(msg,raw,sizeof(raw),11,true,true)==(bit==MOUSE_MOVE_NOCOALESCE),"absolute attributes virtual and unknown mode flags remain blocked");
        raw=packet();raw.data.mouse.usButtonFlags=static_cast<USHORT>(bit);check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"every button and wheel flag remains blocked");
        raw=packet();raw.data.mouse.usButtonData=static_cast<USHORT>(bit);check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"button data remains blocked");
    }
    for(unsigned bit=0;bit<32;++bit){raw=packet();raw.data.mouse.ulRawButtons=1UL<<bit;check(!r::routed_message(msg,raw,sizeof(raw),11,true,true),"raw button state remains blocked");}
}
void adapter_tests(){
    auto msg=message();auto raw=packet();
    r::Snapshot before;check(MineComeReadRawMotionDiagnostics(&before),"diagnostic ABI works before capture");
    bool lease=true;unsigned called=0;
    auto owned=[](auto helper){return helper==7;};
    auto grant=[&](auto owner,auto apply){++called;return lease&&owner==11&&apply(owner);};
    check(a::route(msg,raw,sizeof(raw),11,true,owned,grant),"exact resolved owned world route passes");
    lease=false;check(!a::route(msg,raw,sizeof(raw),11,true,owned,grant),"full pending expiry or focus loss cannot retain world route");
    lease=true;check(!a::route(msg,raw,sizeof(raw),12,true,owned,grant),"different resolved owner cannot borrow lease");
    auto foreign=[](auto){return false;};check(!a::route(msg,raw,sizeof(raw),11,true,foreign,grant),"foreign helper denied before lease callback");
    check(!a::route(msg,raw,sizeof(raw),11,false,owned,grant),"removed or retargeted helper denied");
    raw.data.mouse.usButtonFlags=RI_MOUSE_LEFT_BUTTON_DOWN;check(!a::route(msg,raw,sizeof(raw),11,true,owned,grant),"mixed packet does not reach owner grant");
    raw=packet();msg.wParam=RIM_INPUTSINK;check(!a::route(msg,raw,sizeof(raw),11,true,owned,grant),"sink packet denied before owner grant");
    msg=message();check(!a::route(msg,raw,sizeof(raw),7,true,owned,grant),"main target remains on frozen route");
    check(called==3,"only three eligible helper packets query live lease");
    r::Snapshot after;check(MineComeReadRawMotionDiagnostics(&after),"diagnostic export remains readable");
    check(after.mouse_raw_packets_seen-before.mouse_raw_packets_seen==8&&after.registered_helper_candidates-before.registered_helper_candidates==6,"raw sightings and registered helper candidates counted before owner rejection");
    check(after.helper_moves_passed-before.helper_moves_passed==1&&after.route_owner_rejected-before.route_owner_rejected==4&&after.packet_rejected-before.packet_rejected==2,"pass route and packet counters distinguish decisions");
    unsigned ownership_checks=0;auto destroyed=[&](auto){return ++ownership_checks==1;};
    check(!a::route(msg,raw,sizeof(raw),11,true,destroyed,grant)&&ownership_checks==2,"helper ownership rechecked at lease decision after destruction or reuse");
    auto invalid=after;invalid.size--;check(!MineComeReadRawMotionDiagnostics(&invalid),"wrong diagnostic size rejected");invalid=after;invalid.version++;check(!MineComeReadRawMotionDiagnostics(&invalid),"wrong diagnostic version rejected");
    check(!MineComeReadRawMotionDiagnostics(nullptr),"null diagnostics rejected");
    check(!MineComeAllowRoutedRawMotion(nullptr,nullptr,true),"production wrapper handles null request");
    msg=message();msg.message=WM_MOUSEMOVE;check(!MineComeAllowRoutedRawMotion(&msg,reinterpret_cast<HWND>(11),true),"production wrapper rejects nonraw request");
    DIMOUSESTATE state{};state.lX=12;state.lY=-8;
    check(!minecome::motion::adapter::after_state(99,sizeof(state),&state,DI_OK,[](auto){return true;})&&state.lX==12,"production SDK wrapper instantiated with NOKEYSTATES and real environment");
}
}
int main(){try{registration_tests();policy_tests();adapter_tests();std::cout<<"RAW_MOTION_R3 checks="<<checks<<" PASS\n";return 0;}catch(const std::exception &e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}}
