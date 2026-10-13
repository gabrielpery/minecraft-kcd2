#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include "../reshade/mouse_capture_adapter.hpp"
#include <iostream>
#include <stdexcept>
#include <vector>
namespace m=minecome::mouse;
namespace a=minecome::mouse::adapter;
namespace {
unsigned checks=0;
void check(bool condition,const char *text){++checks;if(!condition)throw std::runtime_error(text);}
m::Policy ready(){m::Policy p;p.add(1,true);p.format(1,16,true);p.cooperative(1,7);return p;}
void policy_tests(){
    m::Policy p;
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"no unobserved device capture");
    p.add(1,true);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"unknown cooperative window rejected");
    p.cooperative(1,7);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"unknown layout rejected");
    p.format(1,16,false);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"unknown or absolute axis mode rejected");
    p.format(1,16,true);
    for(auto duration:{0u,101u,0xffffffffu})check(p.request(7,9,duration,1000,true)==m::Result::bad_argument,"lease bounded to100ms");
    check(p.request(7,0,100,1000,true)==m::Result::bad_argument,"zero token rejected");
    check(p.request(7,9,100,1000,false)==m::Result::unavailable,"owned foreground required");
    check(p.request(7,9,100,1000,true)==m::Result::ok,"known relative mouse starts");
    auto first=p.snapshot(7,1000,true);
    check((first.flags&m::Flag::active)&&first.lease_remaining_ms==100,"snapshot grants bounded lease");
    check(p.request(8,10,100,1001,false)==m::Result::foreign_owner&&(p.snapshot(7,1001,true).flags&m::Flag::active),"foreign request cannot revoke rightful capture");
    check(p.release(7,10)==m::Result::foreign_owner,"foreign release refused");
    check(p.request(7,9,100,1050,true)==m::Result::ok&&p.snapshot(7,1050,true).generation==first.generation,"renewal preserves generation");
    const auto expired=p.snapshot(7,1150,true);
    check(!(expired.flags&m::Flag::active)&&(expired.flags&m::Flag::draining)&&expired.generation>first.generation,"expiry revokes before first pass-through");
    check(p.request(7,9,100,1150,true)==m::Result::draining,"new lease waits for old queue and axes");
    auto ticket=p.begin(1,1151,true);check(ticket.suppress,"expiry drops first successful poll");p.finish(ticket,true,true,false);
    check(!(p.snapshot(7,1152,true).flags&m::Flag::draining)&&!p.begin(1,1152,true).suppress,"drained unowned input passes through");
    check(p.request(7,9,100,1153,true)==m::Result::ok,"new lease after drain");
    check(p.release(7,9)==m::Result::ok,"explicit release marks drain");
    auto old=p.begin(1,1154,false);p.format(1,20,true);p.finish(old,true,true,false);
    check(p.snapshot(7,1155,false).flags&m::Flag::draining,"in-flight old callback cannot clear new generation drain");
    auto fresh=p.begin(1,1155,false);p.finish(fresh,true,false,true);
    check(!(p.snapshot(7,1156,false).flags&m::Flag::draining),"released queue can drain after focus loss");
    p=ready();p.request(7,9,100,1000,true);ticket=p.begin(1,1001,true);p.finish(ticket,false,false,true);
    auto failed=p.snapshot(7,1002,true);
    check(!(failed.flags&(m::Flag::active|m::Flag::eligible))&&failed.drain_failures==1&&failed.reason==static_cast<unsigned>(m::Reason::drain_failed),"drain failure revokes and exposes permanent device fault");
    p=ready();p.request(7,9,100,1000,true);p.axis(1,false);
    check(!(p.snapshot(7,1001,true).flags&m::Flag::active)&&!p.safe_relative(1),"axis change immediately loses safe suppression");
    p=ready();p.add(2,true);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"unknown second mouse cannot be silently ignored");
    p.cooperative(2,8);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable,"other-window mouse rejects whole-process capture without suppressing it");
    p.remove(2);p.request(7,9,100,1000,true);
    p.remove(1);check(!(p.snapshot(7,1001,true).flags&m::Flag::active),"released COM device revokes capture");
    p=ready();for(unsigned i=2;i<=17;++i)p.add(i,true);
    check(p.request(7,9,100,1000,true)==m::Result::unavailable&&p.snapshot(7,1000,true).reason==static_cast<unsigned>(m::Reason::capacity),"bounded registry overflow fails closed");
}
void format_tests(){
    check(a::canonical_format(&c_dfDIMouse)==sizeof(DIMOUSESTATE),"actual SDK canonical mouse format recognized");
    check(a::canonical_format(&c_dfDIMouse2)==sizeof(DIMOUSESTATE2),"actual SDK canonical mouse2 format recognized");
    auto format=c_dfDIMouse;std::vector<DIOBJECTDATAFORMAT> objects(format.rgodf,format.rgodf+format.dwNumObjs);format.rgodf=objects.data();
    format.dwFlags=DIDF_ABSAXIS;check(!a::canonical_format(&format),"absolute data format rejected");format.dwFlags=DIDF_RELAXIS;
    objects[1].dwOfs=objects[0].dwOfs;check(!a::canonical_format(&format),"overlapping axis layout rejected");objects.assign(c_dfDIMouse.rgodf,c_dfDIMouse.rgodf+c_dfDIMouse.dwNumObjs);
    objects[0].dwType|=DIDFT_OUTPUT;check(!a::canonical_format(&format),"output object layout rejected");
    DIPROPDWORD property{};property.diph={sizeof(property),sizeof(property.diph),0,DIPH_DEVICE};property.dwData=DIPROPAXISMODE_REL;
    check(a::relative_property(&property.diph),"authoritative device relative property recognized");property.dwData=DIPROPAXISMODE_ABS;
    check(!a::relative_property(&property.diph),"absolute property never guessed relative");
}
void adapter_tests(){
    unsigned state_calls=0,data_calls=0;
    auto state=[&](DWORD bytes,LPVOID out){++state_calls;check(bytes==16&&out,"drain consumes bounded original state");return DI_OK;};
    auto data=[&](DWORD bytes,LPDIDEVICEOBJECTDATA out,LPDWORD count,DWORD flags){++data_calls;check(bytes==sizeof(DIDEVICEOBJECTDATA)&&!out&&*count==INFINITE&&flags==0,"PEEK drain actually consumes whole original queue");return DI_BUFFEROVERFLOW;};
    check(a::drain(16,state,data)&&state_calls==1&&data_calls==1,"buffer overflow successful drain preserved");
    check(a::drain(16,state,[](DWORD,LPDIDEVICEOBJECTDATA,LPDWORD,DWORD){return DIERR_NOTBUFFERED;}),"non-buffered relative device has no queue to drain");
    check(!a::drain(16,[](DWORD,LPVOID){return DIERR_INPUTLOST;},data),"failed immediate drain cannot certify cleanup");
    check(!a::drain(16,state,[](DWORD,LPDIDEVICEOBJECTDATA,LPDWORD,DWORD){return DIERR_NOTACQUIRED;}),"failed buffered drain cannot certify cleanup");
    auto pending=[](){a::policy=ready();a::policy.request(7,9,100,GetTickCount64(),true);a::policy.release(7,9);};
    pending();DIMOUSESTATE mouse{10,-20,120,{128,128,128,128}};unsigned drains=0;
    check(a::after_state(1,sizeof(mouse),&mouse,DI_OK,[&](std::uint32_t bytes){++drains;return bytes==16;}),"first released immediate sample suppressed");
    const DIMOUSESTATE zero{};check(std::memcmp(&mouse,&zero,sizeof(mouse))==0&&drains==1,"all axes buttons and wheel cleared together");
    mouse.lX=42;check(!a::after_state(1,sizeof(mouse),&mouse,DI_OK,[&](auto){++drains;return true;})&&mouse.lX==42&&drains==1,"subsequent unowned sample untouched");
    pending();mouse.lX=42;check(!a::after_state(1,sizeof(mouse),&mouse,DIERR_INPUTLOST,[&](auto){++drains;return true;})&&mouse.lX==42&&drains==1,"original failed HRESULT never masks or mutates buffer");
    for(auto flags:{0u,static_cast<unsigned>(DIGDD_PEEK)}){pending();DWORD count=3;check(a::after_data(1,sizeof(DIDEVICEOBJECTDATA),&count,flags,DI_BUFFEROVERFLOW,[](auto){return true;})&&count==0,"buffered and PEEK both suppress count without rewriting HRESULT");}
    pending();DWORD count=3;check(!a::after_data(1,sizeof(DIDEVICEOBJECTDATA),&count,DIGDD_PEEK,DIERR_INPUTLOST,[](auto){return true;})&&count==3,"failed buffered operation remains untouched");
    pending();a::policy.axis(1,false);mouse.lX=77;check(!a::after_state(1,sizeof(mouse),&mouse,DI_OK,[](auto){return true;})&&mouse.lX==77,"unknown absolute reconfiguration is never zeroed");
    auto invalid=a::policy.snapshot(7,GetTickCount64(),true);check((invalid.flags&m::Flag::draining)&&!(invalid.flags&(m::Flag::active|m::Flag::eligible)),"unsupported drain cannot claim ownership restored");
    pending();a::policy.format(1,0,false);a::policy.unsupported(1);mouse.lX=99;
    check(!a::after_state(1,sizeof(mouse),&mouse,DI_OK,[](auto){return true;})&&mouse.lX==99&&a::policy.bytes(1)==0,"action-map or Initialize forgets same-size custom layout before original call");
    check(MineComeGetMouseCaptureApi(1,sizeof(m::Api))&& !MineComeGetMouseCaptureApi(2,sizeof(m::Api))&&!MineComeGetMouseCaptureApi(1,sizeof(m::Api)-1),"versioned export refuses incompatible ABI");
    const auto window=CreateWindowExW(0,L"STATIC",L"",0,0,0,0,0,HWND_MESSAGE,nullptr,GetModuleHandleW(nullptr),nullptr);
    check(window!=nullptr,"test owns hidden message window");m::Snapshot snapshot;
    AcquireSRWLockExclusive(&a::mutex);const auto result=a::query(reinterpret_cast<std::uintptr_t>(window),0,&snapshot);ReleaseSRWLockExclusive(&a::mutex);
    check(result==m::Result::busy&&snapshot.flags==0&&snapshot.reason==static_cast<unsigned>(m::Reason::lock_contention),"render API contention cannot claim active ownership");
    DestroyWindow(window);
}
}
int main(){try{policy_tests();format_tests();adapter_tests();std::cout<<"MOUSE_CAPTURE_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception &e){std::cerr<<"MOUSE_CAPTURE_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
