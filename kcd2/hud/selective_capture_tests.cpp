#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include "../reshade/selective_capture_adapter.hpp"
#include <iostream>
#include <stdexcept>
#include <vector>
namespace m=minecome::selective;
namespace a=minecome::selective::adapter;
namespace {
unsigned checks=0;
void check(bool condition,const char *message){++checks;if(!condition)throw std::runtime_error(message);}
m::Policy ready(){m::Policy p;p.add(1,true);p.format(1,16,true);p.cooperative(1,7);return p;}
void policy_tests(){
    auto p=ready();
    check(p.request(7,9,100,m::Mode::none,1000,true)==m::Result::bad_argument,"none cannot capture");
    for(auto duration:{0u,101u,~0u})check(p.request(7,9,duration,m::Mode::buttons,1000,true)==m::Result::bad_argument,"lease bounded");
    check(p.request(7,0,100,m::Mode::buttons,1000,true)==m::Result::bad_argument,"nonzero token required");
    check(p.request(7,9,100,m::Mode::buttons,1000,false)==m::Result::unavailable,"foreground required");
    check(p.request(7,9,100,m::Mode::buttons,1000,true)==m::Result::ok,"buttons starts");
    const auto first=p.snapshot(7,1000,true);
    check(first.flags==(m::active|m::eligible)&&first.mode==m::Mode::buttons&&first.lease_remaining_ms==100,"buttons lease snapshot");
    check(p.request(8,10,100,m::Mode::full,1001,false)==m::Result::foreign_owner,"foreign cannot alter active lease");
    check(p.release(7,10)==m::Result::foreign_owner,"foreign cannot release");
    check(p.request(7,9,100,m::Mode::buttons,1010,true)==m::Result::ok&&p.snapshot(7,1010,true).generation==first.generation,"renew unchanged mode generation");
    check(p.request(7,9,100,m::Mode::full,1011,true)==m::Result::draining,"buttons to full waits device drain");
    const auto transition=p.snapshot(7,1011,true);
    check(transition.flags==(m::active|m::draining)&&transition.mode==m::Mode::full&&transition.token==9&&transition.generation>first.generation,"pending owns strict full mode");
    check(p.request(7,9,100,m::Mode::buttons,1012,true)==m::Result::bad_argument,"cannot reverse pending mode");
    check(p.request(7,9,100,m::Mode::full,1050,true)==m::Result::draining&&p.snapshot(7,1050,true).lease_remaining_ms==100,"own pending renews lease");
    auto t=p.begin(1,1051,true);check(t.suppress&&t.owned&&t.mode==m::Mode::full,"pending callback fully captures");p.finish(t,true,true,false,true);
    check(p.request(7,9,100,m::Mode::full,1052,true)==m::Result::ok&&p.snapshot(7,1052,true).generation==transition.generation,"drain completes same generation");
    check(p.request(7,9,100,m::Mode::buttons,1053,true)==m::Result::draining,"full to buttons needs fresh drain");
    t=p.begin(1,1054,true);p.finish(t,true,false,true,true);
    auto resumed=p.snapshot(7,1054,true);
    check(resumed.mode==m::Mode::buttons&&resumed.flags==(m::active|m::eligible)&&resumed.queue_drains==2,"buttons returns after full drain");
    t=p.begin(1,1055,true);check(t.mode==m::Mode::buttons,"steady callback preserves axes");p.finish(t,true,true,false,false);
    check(p.snapshot(7,1055,true).queue_drains==2,"steady buttons performs no drain");
    const auto expired=p.snapshot(7,1153,true);
    check(!(expired.flags&m::active)&&(expired.flags&m::draining)&&expired.mode==m::Mode::none,"expiry first enters cleanup");
    check(p.request(7,9,100,m::Mode::buttons,1154,true)==m::Result::draining,"cannot reacquire before cleanup");
    t=p.begin(1,1154,false);check(t.mode==m::Mode::full,"expired cleanup ignores focus for drain");p.finish(t,true,true,false,true);
    check(!p.begin(1,1155,false).suppress,"unowned after cleanup passes");
    p=ready();p.request(7,9,100,m::Mode::buttons,1000,true);t=p.begin(1,1001,true);p.release(7,9);p.finish(t,true,true,false,true);
    check(p.snapshot(7,1002,true).flags&m::draining,"stale generation cannot certify cleanup");
    t=p.begin(1,1003,true);p.finish(t,true,true,false,true);check(!(p.snapshot(7,1004,true).flags&m::draining),"fresh generation cleanup completes");
    p=ready();p.add(2,true);p.format(2,20,true);p.cooperative(2,7);p.request(7,9,100,m::Mode::full,1000,true);p.request(7,9,100,m::Mode::buttons,1001,true);
    t=p.begin(1,1002,true);p.finish(t,true,true,false,true);check(p.snapshot(7,1002,true).mode==m::Mode::full,"every tracked device must drain");
    t=p.begin(2,1003,true);p.finish(t,true,true,false,true);check(p.snapshot(7,1003,true).mode==m::Mode::buttons,"last device completes transition");
    p=ready();p.request(7,9,100,m::Mode::buttons,1000,true);t=p.begin(1,1001,true);auto concurrent=p.begin(1,1001,true);
    check(concurrent.suppress&&!concurrent.owned&&!p.current(t)&&!(p.snapshot(7,1001,true).flags&m::active),"concurrent device IO revokes before shared queue access");p.finish(t,true,true,false,false);
    p=ready();p.request(7,9,100,m::Mode::buttons,1000,true);t=p.begin(1,1001,true);p.finish(t,false,true,false,false);
    check(p.snapshot(7,1001,true).drain_failures==1&&!(p.snapshot(7,1001,true).flags&m::eligible),"failed drain permanently refuses device");
    p=ready();p.axis(1,false);check(p.request(7,9,100,m::Mode::buttons,1000,true)==m::Result::unavailable,"absolute format rejected");
    p=ready();p.add(2,true);check(p.request(7,9,100,m::Mode::buttons,1000,true)==m::Result::unavailable,"unconfigured second device rejected");
    p=ready();for(unsigned i=2;i<=17;++i)p.add(i,true);check(p.snapshot(7,1000,true).reason==static_cast<unsigned>(m::Reason::capacity),"registry capacity explicit");
}
struct Original {
    std::vector<DIDEVICEOBJECTDATA> events;
    bool overflow=false;HRESULT failure=DI_OK;unsigned calls=0,drains=0;
    HRESULT read(DWORD bytes,LPDIDEVICEOBJECTDATA output,LPDWORD count,DWORD flags){
        ++calls;if(FAILED(failure))return failure;
        if(!count||(bytes!=sizeof(DIDEVICEOBJECTDATA)&&bytes!=sizeof(DIDEVICEOBJECTDATA_DX3))||(flags&~DIGDD_PEEK))return DIERR_INVALIDPARAM;
        const auto amount=std::min<std::size_t>(*count,events.size());const auto hr=overflow?DI_BUFFEROVERFLOW:DI_OK;
        if(output)for(std::size_t i=0;i<amount;++i)std::memcpy(reinterpret_cast<BYTE *>(output)+i*bytes,&events[i],bytes);
        *count=static_cast<DWORD>(amount);
        if(!(flags&DIGDD_PEEK)){events.erase(events.begin(),events.begin()+amount);overflow=false;}
        return hr;
    }
    bool drain(std::uint32_t bytes){++drains;events.clear();overflow=false;return bytes==16||bytes==20;}
};
DIDEVICEOBJECTDATA record(DWORD offset,DWORD value,DWORD seq){return {offset,value,seq+100,seq,static_cast<ULONG_PTR>(seq+200)};}
void arm(m::Mode mode=m::Mode::buttons){a::revoke_pending=false;a::policy=ready();check(a::policy.request(7,9,100,mode,1000,true)==m::Result::ok,"adapter arm");}
HRESULT read(Original &original,DIDEVICEOBJECTDATA *output,DWORD &count,DWORD flags=0,DWORD bytes=sizeof(DIDEVICEOBJECTDATA)){
    HRESULT result=E_FAIL;
    check(a::before_data_with_environment(1,bytes,output,&count,flags,result,[&](auto b,auto o,auto c,auto f){return original.read(b,o,c,f);},[&](auto b){return original.drain(b);},[]{return a::Environment{1001,true};}),"owned adapter handles data");
    return result;
}
void buffered_tests(){
    arm();Original source;source.events={record(12,128,1),record(0,17,2),record(13,0,3),record(4,static_cast<DWORD>(-3),4),record(8,120,5)};
    DIDEVICEOBJECTDATA output[8]{};DWORD count=1;
    check(read(source,output,count,DIGDD_PEEK)==DI_OK&&count==1&&output[0].dwOfs==0&&output[0].dwData==17,"button prefix cannot starve PEEK axes");
    check(source.events.empty()&&source.drains==0,"owned FIFO consumes original without full drain");
    const auto first=output[0];count=1;check(read(source,output,count,DIGDD_PEEK)==DI_OK&&std::memcmp(&first,output,sizeof(first))==0,"repeated PEEK preserves full record");
    count=8;check(read(source,nullptr,count,DIGDD_PEEK)==DI_OK&&count==3,"null peek counts retained axes");
    source.events={record(0,7,6)};count=1;check(read(source,output,count)==DI_OK&&output[0].dwSequence==2,"nonpeek oldest axis first");
    count=1;check(read(source,nullptr,count)==DI_OK&&count==1,"null nonpeek discards exactly requested axes");
    count=8;check(read(source,output,count)==DI_OK&&count==2&&output[0].dwSequence==5&&output[1].dwSequence==6,"new axes follow old FIFO axes");
    count=8;check(read(source,output,count)==DI_OK&&count==0,"consumed queue empty");
    auto snapshot=a::policy.snapshot(7,1001,true);check(snapshot.button_records_filtered==2&&snapshot.queue_drains==0,"filter counters distinguish from drains");
    arm();source={};source.events={record(0,12,1),record(4,13,2)};source.overflow=true;
    count=1;check(read(source,output,count,DIGDD_PEEK)==DI_BUFFEROVERFLOW&&count==1,"physical overflow surfaced for virtual PEEK");
    count=1;check(read(source,output,count,DIGDD_PEEK)==DI_BUFFEROVERFLOW,"PEEK does not clear virtual overflow");
    count=0;check(read(source,nullptr,count)==DI_BUFFEROVERFLOW&&count==0,"zero-count nonpeek acknowledges overflow without consuming");
    count=8;check(read(source,output,count)==DI_OK&&count==2,"zero-count preserved both axes");
    check(a::policy.snapshot(7,1001,true).buffer_overflows==1,"one physical overflow accounted");
    arm();source={};source.events={record(12,128,1),record(4,22,2),record(0,33,3)};
    std::array<DIDEVICEOBJECTDATA_DX3,3> old_output{};count=3;
    check(read(source,reinterpret_cast<DIDEVICEOBJECTDATA *>(old_output.data()),count,0,sizeof(DIDEVICEOBJECTDATA_DX3))==DI_OK&&count==2,"DX3 stride accepted");
    check(old_output[0].dwOfs==4&&old_output[0].dwData==22&&old_output[0].dwTimeStamp==102&&old_output[0].dwSequence==2&&old_output[1].dwOfs==0&&old_output[2].dwData==0,"DX3 metadata preserved without overwrite");
    arm();source={};source.events={record(12,128,1),record(0,3,2)};count=INFINITE;
    check(read(source,nullptr,count)==DI_OK&&count==1&&a::policy.buffer(1)->size()==0,"null INFINITE flush discards all retained axes");
    arm();source={};source.events={record(12,128,1),record(13,0,2)};count=1;
    check(read(source,output,count,DIGDD_PEEK)==DI_OK&&count==0&&source.events.empty(),"buttons-only physical queue consumes rather than starves");
    source.events={record(4,55,3)};count=1;check(read(source,output,count)==DI_OK&&count==1&&output[0].dwData==55,"axis after button-only peek remains deliverable");
    arm();source={};for(unsigned i=0;i<m::Buffer::capacity;++i)source.events.push_back(record(0,i,i));count=INFINITE;
    check(read(source,nullptr,count,DIGDD_PEEK)==DI_OK&&count==m::Buffer::capacity,"bounded queue supports full capacity");
    source.events={record(0,1,999)};count=1;
    check(read(source,output,count)==DIERR_INPUTLOST&&count==0&&source.drains==1&&!(a::policy.snapshot(7,1001,true).flags&m::active),"overflow capacity explicitly revokes instead of losing axes silently");
    arm();source={};source.events={record(99,2,1)};count=1;
    check(read(source,output,count)==DIERR_INPUTLOST&&count==0&&source.drains==1,"unknown object layout revokes and drains");
    arm();source={};source.failure=DIERR_INPUTLOST;count=7;output[0].dwData=99;
    check(read(source,output,count)==DIERR_INPUTLOST&&count==7&&output[0].dwData==99,"failed original call retains caller output and HRESULT");
    arm();source={};source.events={record(0,4,1)};count=1;HRESULT result=DI_OK;unsigned samples=0;
    check(a::before_data_with_environment(1,sizeof(DIDEVICEOBJECTDATA),output,&count,0,result,[&](auto b,auto o,auto c,auto f){return source.read(b,o,c,f);},[&](auto b){return source.drain(b);},[&]{return a::Environment{++samples==1?1001ull:1100ull,true};})&&result==DIERR_INPUTLOST&&count==0&&source.drains==1,"expiry during original IO drops axes and drains");
    arm();source={};source.events={record(0,4,1)};count=1;samples=0;
    check(a::before_data_with_environment(1,sizeof(DIDEVICEOBJECTDATA),output,&count,0,result,[&](auto b,auto o,auto c,auto f){return source.read(b,o,c,f);},[&](auto b){return source.drain(b);},[&]{return a::Environment{1001,++samples==1};})&&result==DIERR_INPUTLOST&&count==0&&source.drains==1,"focus loss during original IO drops axes and drains");
    arm();source={};source.events={record(0,4,1)};count=1;bool changed=false;
    check(a::before_data_with_environment(1,sizeof(DIDEVICEOBJECTDATA),output,&count,0,result,[&](auto b,auto o,auto c,auto f){
        if(!changed){changed=true;check(a::policy.request(7,9,100,m::Mode::full,1001,true)==m::Result::draining,"mode can change while original callback runs");}
        return source.read(b,o,c,f);
    },[&](auto b){return source.drain(b);},[]{return a::Environment{1001,true};})&&result==DIERR_INPUTLOST&&count==0&&source.drains==1,"old buffered generation never publishes axes after mode change");
    check(a::policy.snapshot(7,1001,true).flags&m::draining,"old callback drain cannot satisfy new mode generation");
    count=1;check(read(source,output,count)==DI_OK&&count==0&&source.drains==2&&!(a::policy.snapshot(7,1001,true).flags&m::draining),"new device callback finalizes transition");
    arm();source={};source.events={record(0,4,1)};count=1;
    check(read(source,output,count,0,1)==DIERR_INVALIDPARAM&&!(a::policy.snapshot(7,1001,true).flags&m::active),"invalid struct size keeps original error and revokes");
    arm();source={};source.events={record(0,4,1)};count=1;
    check(read(source,output,count,2)==DIERR_INVALIDPARAM&&!(a::policy.snapshot(7,1001,true).flags&m::active),"unsupported flags keep original error and revoke");
    arm();source={};source.events={record(0,10,1)};count=1;read(source,output,count,DIGDD_PEEK);
    check(a::policy.request(7,9,100,m::Mode::full,1002,true)==m::Result::draining,"buffered transition requested");
    count=1;check(read(source,output,count,DIGDD_PEEK)==DI_OK&&count==0&&source.drains==1&&a::policy.buffer(1)->size()==0,"transition flushes virtual and physical queues");
    check(a::policy.snapshot(7,1002,true).mode==m::Mode::full&&!(a::policy.snapshot(7,1002,true).flags&m::draining),"buffered drain completes transition");
}
void immediate_tests(){
    arm();DIMOUSESTATE mouse{12,-3,120,{128,128,128,128}};unsigned drains=0;
    auto discard=[&](auto bytes){++drains;return bytes==sizeof(mouse);};
    auto env=[]{return a::Environment{1001,true};};
    check(a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env)&&mouse.lX==12&&mouse.lY==-3&&mouse.lZ==120,"world immediate preserves XYZ exactly");
    check(mouse.rgbButtons[0]==0&&mouse.rgbButtons[3]==0&&drains==0,"world buttons zero without axis drain");
    check(a::policy.request(7,9,100,m::Mode::full,1002,true)==m::Result::draining,"immediate inventory transition pending");
    mouse={12,-3,120,{128,128,128,128}};check(a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env),"full transition handled");
    DIMOUSESTATE zero{};check(std::memcmp(&mouse,&zero,sizeof(mouse))==0&&drains==1,"transition clears all state and drains");
    check(a::policy.request(7,9,100,m::Mode::buttons,1003,true)==m::Result::draining,"immediate world transition pending");
    mouse.lX=99;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env);check(mouse.lX==0&&drains==2,"world return first drains inventory motion");
    mouse.lX=5;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env);check(mouse.lX==5&&drains==2,"fresh world motion passes after drain");
    a::policy.release(7,9);mouse.lX=9;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env);check(mouse.lX==0&&drains==3,"release first sample clears retained state");
    mouse.lX=8;check(!a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,env)&&mouse.lX==8,"unowned following sample untouched");
    arm();mouse.lX=88;check(!a::after_state_with_environment(1,sizeof(mouse),&mouse,DIERR_INPUTLOST,discard,env)&&mouse.lX==88,"failed state output untouched");
    arm();mouse.lX=88;unsigned samples=0;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,[&]{return a::Environment{++samples==1?1001ull:1100ull,true};});check(mouse.lX==0,"expiry between read and publication suppresses axes");
    arm();mouse.lX=88;samples=0;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,[&]{return a::Environment{++samples<=2?1001ull:1100ull,true};});
    check(mouse.lX==88&&samples==2,"buttons publication and finish have one final sampled lock");
    arm();mouse.lX=88;samples=0;a::after_state_with_environment(1,sizeof(mouse),&mouse,DI_OK,discard,[&]{
        if(++samples==2)a::policy.request(7,9,100,m::Mode::full,1001,true);
        return a::Environment{1001,true};
    });check(mouse.lX==0&&(a::policy.snapshot(7,1001,true).flags&m::draining),"mode changed at publication zeros axes but cannot certify new generation");
    arm();a::policy.format(1,20,true);a::policy.request(7,9,100,m::Mode::buttons,1001,true);
    auto ticket=a::policy.begin(1,1001,true);a::policy.finish(ticket,true,true,false,true);a::policy.request(7,9,100,m::Mode::buttons,1001,true);
    DIMOUSESTATE2 mouse2{11,22,33,{128,128,128,128,128,128,128,128}};
    check(a::after_state_with_environment(1,sizeof(mouse2),&mouse2,DI_OK,[](auto){return true;},env)&&mouse2.lX==11&&mouse2.lY==22&&mouse2.lZ==33&&mouse2.rgbButtons[7]==0,"extended eight-button format preserves axes");
}
void contract_tests(){
    check(a::canonical_format(&c_dfDIMouse)==16&&a::canonical_format(&c_dfDIMouse2)==20,"SDK canonical formats accepted");
    auto format=c_dfDIMouse;format.dwFlags=DIDF_ABSAXIS;check(!a::canonical_format(&format),"absolute format rejected");
    check(MineComeGetSelectiveMouseCaptureApi(2,sizeof(m::Api))&&!MineComeGetSelectiveMouseCaptureApi(1,sizeof(m::Api))&&!MineComeGetSelectiveMouseCaptureApi(2,sizeof(m::Api)-1),"versioned export refuses incompatible API");
    check(a::drain(16,[](DWORD,LPVOID){return DI_OK;},[](DWORD,LPDIDEVICEOBJECTDATA,LPDWORD,DWORD){return DIERR_NOTBUFFERED;}),"unbuffered state device can drain");
    check(!a::drain(16,[](DWORD,LPVOID){return DIERR_INPUTLOST;},[](DWORD,LPDIDEVICEOBJECTDATA,LPDWORD,DWORD){return DI_OK;}),"failed physical state cannot certify drain");
    m::Buffer buffer;for(unsigned i=0;i<m::Buffer::capacity;++i)check(buffer.push({0,i,0,i,0}),"fixed FIFO fill");
    check(!buffer.push({}),"FIFO does not allocate or overwrite");buffer.consume(128);
    for(unsigned i=0;i<128;++i)check(buffer.push({0,i+256,0,i+256,0}),"wrapped FIFO fill");
    for(unsigned i=0;i<256;++i)check(buffer.at(i).data==i+128,"wrapped FIFO preserves order");
    buffer.overflow=true;buffer.clear();check(!buffer.size()&&!buffer.overflow,"clear resets queue and overflow");
    check(!MineComeSelectiveCursorLook(),"no actual owned foreground lease cannot bypass cursor hooks");
}
void contention_tests(){
    // Hidden, process-owned test HWND. No focus changes, OS input or game.
    const auto window=CreateWindowExW(0,L"STATIC",L"MineCome capture contention test",0,0,0,1,1,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    check(window!=nullptr,"contention fixture HWND created");
    const auto owner=reinterpret_cast<std::uintptr_t>(window);
    auto prepare=[&]{
        a::revoke_pending=false;a::policy=ready();a::policy.cooperative(1,owner);
        check(a::policy.request(owner,9,100,m::Mode::buttons,1000,true)==m::Result::ok,"contention fixture captured");
        return a::policy.snapshot(owner,1000,true).generation;
    };
    auto generation=prepare();m::Snapshot snapshot;
    AcquireSRWLockExclusive(&a::mutex);
    const auto observed=a::query(owner,9,&snapshot);
    ReleaseSRWLockExclusive(&a::mutex);
    check(observed==m::Result::busy&&snapshot.flags==0&&snapshot.reason==static_cast<unsigned>(m::Reason::lock_contention),"busy query certifies no capture");
    check(!a::revoke_pending.load(),"busy read cannot revoke original capture");
    {a::Guard lock;}
    snapshot=a::policy.snapshot(owner,1050,true);
    check(snapshot.generation==generation&&(snapshot.flags&m::active)&&snapshot.lease_remaining_ms==50,"read contention preserves generation and original deadline");
    snapshot=a::policy.snapshot(owner,1100,true);
    check(!(snapshot.flags&m::active)&&snapshot.reason==static_cast<unsigned>(m::Reason::lease_expired),"busy query never renews expired ownership");
    for(const bool release:{false,true}){
        generation=prepare();snapshot={};
        AcquireSRWLockExclusive(&a::mutex);
        const auto result=release?a::release(owner,9,&snapshot):a::request(owner,9,100,m::Mode::buttons,&snapshot);
        ReleaseSRWLockExclusive(&a::mutex);
        check(result==m::Result::busy&&snapshot.flags==0&&a::revoke_pending.load(),"mutating contention remains fail closed");
        {a::Guard lock;}
        snapshot=a::policy.snapshot(owner,1001,true);
        check(!(snapshot.flags&m::active)&&snapshot.generation==generation+1&&snapshot.reason==static_cast<unsigned>(m::Reason::lock_contention),"failed mutation invalidates existing generation");
    }
    prepare();a::revoke_pending=true;snapshot={};
    AcquireSRWLockExclusive(&a::mutex);a::query(owner,9,&snapshot);ReleaseSRWLockExclusive(&a::mutex);
    check(a::revoke_pending.load(),"busy read cannot clear pending mutation revocation");
    {a::Guard lock;}
    check(!(a::policy.snapshot(owner,1001,true).flags&m::active),"pending revocation survives read deferral");
    a::policy={};a::revoke_pending=false;DestroyWindow(window);
}
}
int main(){try{policy_tests();buffered_tests();immediate_tests();contract_tests();contention_tests();std::cout<<"SELECTIVE_CAPTURE_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception &e){std::cerr<<"SELECTIVE_CAPTURE_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
