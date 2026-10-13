#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include "../reshade/motion_capture_adapter.hpp"
#include <iostream>
#include <stdexcept>
namespace m=minecome::motion;
namespace a=minecome::motion::adapter;
namespace s=minecome::selective;
namespace sa=minecome::selective::adapter;
namespace {
unsigned checks=0;
void check(bool okay,const char *why){++checks;if(!okay)throw std::runtime_error(why);}
MSG message(UINT kind=WM_MOUSEMOVE){MSG result{};result.hwnd=reinterpret_cast<HWND>(7);result.message=kind;result.wParam=MK_SHIFT|MK_CONTROL|m::held_mouse_buttons;result.lParam=0x12345678;result.time=123;result.pt={42,73};return result;}
RAWINPUT raw_mouse(){RAWINPUT raw{};raw.header.dwType=RIM_TYPEMOUSE;raw.header.dwSize=sizeof(RAWINPUTHEADER)+sizeof(RAWMOUSE);raw.header.hDevice=reinterpret_cast<HANDLE>(13);raw.header.wParam=RIM_INPUT;raw.data.mouse.lLastX=12;raw.data.mouse.lLastY=-7;return raw;}
void window_tests(){
    auto original=message();auto move=original;
    check(m::window_move(move,7,true),"owned world movement admitted");
    check(move.wParam==(MK_SHIFT|MK_CONTROL),"all mouse-button bits stripped from returned MSG");
    original.wParam=move.wParam;check(std::memcmp(&original,&move,sizeof(move))==0,"coordinates, time, window, kind and other fields preserved");
    for(const auto kind:{WM_LBUTTONDOWN,WM_LBUTTONUP,WM_LBUTTONDBLCLK,WM_RBUTTONDOWN,WM_RBUTTONUP,WM_RBUTTONDBLCLK,
         WM_MBUTTONDOWN,WM_MBUTTONUP,WM_XBUTTONDOWN,WM_XBUTTONUP,WM_MOUSEWHEEL,WM_MOUSEHWHEEL,WM_NCMOUSEMOVE,WM_KEYDOWN,WM_INPUT,WM_NULL}){
        move=message(kind);original=move;check(!m::window_move(move,7,true)&&std::memcmp(&original,&move,sizeof(move))==0,"nonmotion messages never bypass block");
    }
    for(unsigned combinations=0;combinations<32;++combinations){
        constexpr WPARAM buttons[]{MK_LBUTTON,MK_RBUTTON,MK_MBUTTON,MK_XBUTTON1,MK_XBUTTON2};
        move=message();move.wParam=MK_SHIFT;
        for(unsigned bit=0;bit<5;++bit)if(combinations&(1u<<bit))move.wParam|=buttons[bit];
        check(m::window_move(move,7,true)&&move.wParam==MK_SHIFT,"every held-button combination stripped");
    }
    move=message();original=move;
    check(!m::window_move(move,8,true)&&std::memcmp(&original,&move,sizeof(move))==0,"different HWND cannot pass");
    check(!m::window_move(move,0,true),"zero owner rejected");
    check(!m::window_move(move,7,false)&&std::memcmp(&original,&move,sizeof(move))==0,"inventory pending expiry and foreground loss preserve block");
    // A posted message passes through queue-time eligibility again. Its earlier
    // world-mode admission is not cached across a mode transition.
    check(m::window_move(move,7,true),"posted world message sanitized before enqueue");
    check(!m::window_move(move,7,false),"posted motion cannot retain eligibility after full-mode transition");
}
void raw_tests(){
    auto raw=raw_mouse();auto msg=message(WM_INPUT);msg.wParam=RIM_INPUT;
    check(m::pure_relative_xy(raw,sizeof(raw))&&m::raw_message(msg,raw,sizeof(raw),7,true),"exact foreground pure relative XY packet admitted");
    const auto original=raw;
    check(std::memcmp(&original,&raw,sizeof(raw))==0,"admission never edits raw handle contents or local copy");
    raw.data.mouse.usFlags=MOUSE_MOVE_NOCOALESCE;check(m::pure_relative_xy(raw,sizeof(raw)),"relative no-coalesce flag preserves original movement");
    for(unsigned flag=1;flag<=0x8000;flag<<=1){
        if(flag==MOUSE_MOVE_NOCOALESCE)continue;
        raw=raw_mouse();raw.data.mouse.usFlags=static_cast<USHORT>(flag);check(!m::pure_relative_xy(raw,sizeof(raw)),"absolute virtual attributes and unknown mode flags blocked");
    }
    for(unsigned flag=1;flag<=0x8000;flag<<=1){
        raw=raw_mouse();raw.data.mouse.usButtonFlags=static_cast<USHORT>(flag);check(!m::pure_relative_xy(raw,sizeof(raw)),"every button wheel and unknown action flag blocked");
    }
    for(unsigned bit=0;bit<16;++bit){raw=raw_mouse();raw.data.mouse.usButtonData=static_cast<USHORT>(1u<<bit);check(!m::pure_relative_xy(raw,sizeof(raw)),"button data without flag blocked");}
    for(unsigned bit=0;bit<32;++bit){raw=raw_mouse();raw.data.mouse.ulRawButtons=1u<<bit;check(!m::pure_relative_xy(raw,sizeof(raw)),"raw held buttons blocked");}
    raw=raw_mouse();raw.data.mouse.lLastX=0;check(m::pure_relative_xy(raw,sizeof(raw)),"Y-only movement admitted");
    raw.data.mouse.lLastY=0;check(!m::pure_relative_xy(raw,sizeof(raw)),"no movement packet not broadened");
    raw=raw_mouse();raw.data.mouse.lLastY=0;check(m::pure_relative_xy(raw,sizeof(raw)),"X-only movement admitted");
    raw.data.mouse.lLastX=LONG_MIN;raw.data.mouse.lLastY=LONG_MAX;check(m::pure_relative_xy(raw,sizeof(raw)),"signed movement range passed unchanged");
    raw=raw_mouse();raw.header.dwType=RIM_TYPEKEYBOARD;check(!m::pure_relative_xy(raw,sizeof(raw)),"keyboard raw input never admitted");
    raw.header.dwType=RIM_TYPEHID;check(!m::pure_relative_xy(raw,sizeof(raw)),"HID raw input never admitted");
    raw=raw_mouse();raw.header.hDevice=nullptr;check(!m::pure_relative_xy(raw,sizeof(raw)),"unidentified raw device blocked");
    raw=raw_mouse();raw.header.wParam=RIM_INPUTSINK;check(!m::pure_relative_xy(raw,sizeof(raw)),"background raw record blocked");
    for(unsigned size=0;size<sizeof(raw);++size){raw=raw_mouse();check(!m::pure_relative_xy(raw,size),"truncated raw result rejected");}
    for(auto size:{0u,static_cast<unsigned>(sizeof(RAWINPUTHEADER)),static_cast<unsigned>(sizeof(raw)-1),static_cast<unsigned>(sizeof(raw)+1),~0u}){
        raw=raw_mouse();raw.header.dwSize=size;check(!m::pure_relative_xy(raw,sizeof(raw)),"noncanonical record size rejected");
    }
    raw=raw_mouse();check(!m::raw_message(msg,raw,sizeof(raw),8,true),"raw different target HWND rejected");
    check(!m::raw_message(msg,raw,sizeof(raw),0,true),"raw zero owner rejected");
    check(!m::raw_message(msg,raw,sizeof(raw),7,false),"raw full pending lost lease or focus rejected");
    msg.wParam=RIM_INPUTSINK;check(!m::raw_message(msg,raw,sizeof(raw),7,true),"background WM_INPUT message rejected");
    msg=message();check(!m::raw_message(msg,raw,sizeof(raw),7,true),"raw exception applies only to WM_INPUT");
}
void state_and_diagnostics_tests(){
    check(!MineComeReadMotionDiagnostics(nullptr),"null diagnostic buffer rejected");
    m::Snapshot snapshot;snapshot.version=2;check(!MineComeReadMotionDiagnostics(&snapshot),"wrong diagnostics version rejected");
    snapshot={};snapshot.size=63;check(!MineComeReadMotionDiagnostics(&snapshot),"wrong diagnostics size rejected");
    snapshot={};check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.size==64&&snapshot.version==1,"diagnostics v1 ABI64 accepted");
    sa::revoke_pending=false;sa::policy={};sa::policy.add(1,true);sa::policy.format(1,16,true);sa::policy.cooperative(1,7);
    check(sa::policy.request(7,9,100,s::Mode::buttons,1000,true)==s::Result::ok,"state diagnostic fixture armed");
    DIMOUSESTATE mouse{12,-7,120,{128,128,128,128}};unsigned drains=0;
    auto discard=[&](auto bytes){++drains;return bytes==16;};auto env=[]{return sa::Environment{1001,true};};
    check(a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env)&&mouse.lX==12&&mouse.lY==-7&&mouse.rgbButtons[0]==0,"instrumented adapter preserves frozen v2 behavior");
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.state_xy_observed==1&&snapshot.state_xy_passed==1&&drains==0,"nonzero original and returned axes counted");
    mouse={0,0,120,{128}};a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env);
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.state_xy_observed==1&&snapshot.state_xy_passed==1,"wheel without XY does not claim camera motion");
    check(sa::policy.request(7,9,100,s::Mode::full,1001,true)==s::Result::draining,"inventory state fixture changes mode");
    mouse.lX=99;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env);
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.state_xy_observed==2&&snapshot.state_xy_passed==1&&mouse.lX==0&&drains==1,"full capture counts observed motion but never passed motion");
    mouse.lX=88;check(!a::after_state_with_environment(1,sizeof(mouse),&mouse,DIERR_INPUTLOST,discard,env),"failed state unmodified");
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.state_xy_observed==2&&snapshot.state_xy_passed==1,"failed state not counted as handled");
    mouse.lX=88;check(!a::after_state_with_environment(99,sizeof(mouse),&mouse,DI_OK,discard,env),"unowned device state unmodified");
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.state_xy_observed==2,"unowned device not counted");
    MineComeObserveBlockedRawMouse();MineComeObserveBlockedHookMotion();
    check(MineComeReadMotionDiagnostics(&snapshot)&&snapshot.raw_buffer_blocked==1&&snapshot.hook_motion_blocked==1,"blocked alternative paths measured without unblocking");
    const auto before=snapshot;check(MineComeReadMotionDiagnostics(&snapshot)&&std::memcmp(&snapshot,&before,sizeof(snapshot))==0,"diagnostic query is read-only");
    auto move=message();const auto original=move;check(!MineComeAllowMotionMessage(&move)&&std::memcmp(&move,&original,sizeof(move))==0,"fake HWND cannot obtain actual foreground admission");
    WPARAM keys=m::held_mouse_buttons;check(!MineComeAllowMotionPost(reinterpret_cast<HWND>(7),&keys)&&keys==m::held_mouse_buttons,"failed posted admission leaves original keys unchanged");
    check(!MineComeAllowMotionMessage(nullptr)&&!MineComeAllowMotionPost(nullptr,nullptr),"null routing inputs safely rejected");
}
}
int main(){try{window_tests();raw_tests();state_and_diagnostics_tests();std::cout<<"MOTION_CAPTURE_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception &e){std::cerr<<"MOTION_CAPTURE_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
