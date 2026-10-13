#pragma once
// Original MineCome adapter, compiled in the pinned ReShade dinput8.cpp hook
// chain. Windows SDK dinput.h defines the interface slots and data contracts.
#include "selective_capture_policy.hpp"
#include <atomic>
#include <cstring>

namespace minecome::selective::adapter {
inline SRWLOCK mutex=SRWLOCK_INIT;
inline Policy policy;
inline std::atomic<bool> revoke_pending{false};
struct Guard {
    Guard(){AcquireSRWLockExclusive(&mutex);if(revoke_pending.exchange(false))policy.invalidate(Reason::lock_contention);}
    ~Guard(){ReleaseSRWLockExclusive(&mutex);}
};
inline bool owned_window(std::uintptr_t value,bool foreground) {
    const auto window=reinterpret_cast<HWND>(value);DWORD pid=0;
    return window&&IsWindow(window)&&GetWindowThreadProcessId(window,&pid)&&pid==GetCurrentProcessId()&&
        (!foreground||(IsWindowVisible(window)&&!IsIconic(window)&&GetForegroundWindow()==window));
}
inline bool relative_property(LPCDIPROPHEADER value) {
    return value&&value->dwSize==sizeof(DIPROPDWORD)&&value->dwHeaderSize==sizeof(DIPROPHEADER)&&value->dwHow==DIPH_DEVICE&&value->dwObj==0&&
        reinterpret_cast<const DIPROPDWORD *>(value)->dwData==DIPROPAXISMODE_REL;
}
inline std::uint32_t canonical_format(LPCDIDATAFORMAT format) {
    if(!format||format->dwSize!=sizeof(DIDATAFORMAT)||format->dwObjSize!=sizeof(DIOBJECTDATAFORMAT)||format->dwFlags!=DIDF_RELAXIS||!format->rgodf)return 0;
    const unsigned buttons=format->dwDataSize==sizeof(DIMOUSESTATE)?4:format->dwDataSize==sizeof(DIMOUSESTATE2)?8:0;
    if(!buttons||format->dwNumObjs!=3+buttons)return 0;
    unsigned seen=0;
    for(unsigned i=0;i<format->dwNumObjs;++i) {
        const auto &object=format->rgodf[i];unsigned index=99;
        const auto type=DIDFT_GETTYPE(object.dwType);
        if(object.dwFlags||(object.dwType&(DIDFT_FFACTUATOR|DIDFT_FFEFFECTTRIGGER|DIDFT_OUTPUT|DIDFT_VENDORDEFINED|DIDFT_ALIAS)))return 0;
        if((type==DIDFT_AXIS||type==DIDFT_RELAXIS)&&object.pguid) {
            if(*object.pguid==GUID_XAxis&&object.dwOfs==offsetof(DIMOUSESTATE,lX))index=0;
            if(*object.pguid==GUID_YAxis&&object.dwOfs==offsetof(DIMOUSESTATE,lY))index=1;
            if(*object.pguid==GUID_ZAxis&&object.dwOfs==offsetof(DIMOUSESTATE,lZ))index=2;
        } else if((type==DIDFT_BUTTON||type==DIDFT_PSHBUTTON)&&(!object.pguid||*object.pguid==GUID_Button)&&
                  object.dwOfs>=offsetof(DIMOUSESTATE,rgbButtons)&&object.dwOfs<offsetof(DIMOUSESTATE,rgbButtons)+buttons)
            index=3+object.dwOfs-static_cast<unsigned>(offsetof(DIMOUSESTATE,rgbButtons));
        if(index>=11||(seen&(1u<<index)))return 0;seen|=1u<<index;
    }
    return seen==((1u<<(3+buttons))-1)?format->dwDataSize:0;
}
template<class State,class Data> bool drain(std::uint32_t bytes,State state,Data data) {
    if(bytes!=sizeof(DIMOUSESTATE)&&bytes!=sizeof(DIMOUSESTATE2))return false;
    DIMOUSESTATE2 discarded{};if(FAILED(state(bytes,&discarded)))return false;
    DWORD count=INFINITE;const auto hr=data(sizeof(DIDEVICEOBJECTDATA),nullptr,&count,0);
    return SUCCEEDED(hr)||hr==DIERR_NOTBUFFERED;
}
struct Environment {std::uint64_t now;bool valid;};
inline Environment environment(){return {GetTickCount64(),owned_window(policy.window(),true)};}
// The environment provider separates OS ownership/clock sampling from the
// deterministic adapter logic. Production always uses environment() below.
template<class Drain,class Sample> bool after_state_with_environment(std::uintptr_t key,DWORD bytes,LPVOID output,HRESULT original,Drain discard,Sample sample) {
    if(FAILED(original))return false;
    Policy::Ticket ticket;std::uint32_t expected=0;
    {Guard lock;const auto env=sample();ticket=policy.begin(key,env.now,env.valid);expected=policy.bytes(key);
        if(ticket.suppress&&(!policy.safe_relative(key)||!output||bytes!=expected)){policy.unsupported(key);policy.finish(ticket,false,true,false,false);return false;}}
    if(!ticket.suppress)return false;
    // A concurrent callback cannot borrow this device's virtual queue. Clear
    // only the known canonical output and leave its original owner to drain.
    if(!ticket.owned){std::memset(output,0,bytes);return true;}
    bool full=ticket.mode==Mode::full;
    {Guard lock;const auto env=sample();policy.tick(env.now,env.valid);if(!policy.current(ticket))full=true;
        if(!full){
            std::memset(static_cast<LPBYTE>(output)+offsetof(DIMOUSESTATE,rgbButtons),0,bytes - offsetof(DIMOUSESTATE,rgbButtons));
            // Axis publication and completion have one linearization point.
            // No later validity sample can observe a lost lease after we chose
            // to pass axes through and still return the preserved sample.
            policy.finish(ticket,true,true,false,false);return true;
        }
        std::memset(output,0,bytes);}
    const bool drained=discard(expected);
    {Guard lock;const auto env=sample();policy.tick(env.now,env.valid);policy.finish(ticket,drained,true,false,full);}
    return true;
}

// Called before the ordinary hook-chain GetDeviceData. The owned buttons mode
// virtualizes a bounded FIFO so PEEK cannot be starved by a suppressed prefix.
// SDK semantics: learn.microsoft.com/.../ee417894(v=vs.85), inspected 2026-10-13.
template<class Original,class Drain,class Sample> bool before_data_with_environment(std::uintptr_t key,DWORD bytes,LPDIDEVICEOBJECTDATA output,LPDWORD count,DWORD flags,HRESULT &result,Original original,Drain discard,Sample sample) {
    Policy::Ticket ticket;std::uint32_t expected=0;
    {Guard lock;const auto env=sample();ticket=policy.begin(key,env.now,env.valid);expected=policy.bytes(key);}
    if(!ticket.suppress)return false;
    if(!ticket.owned){if(count)*count=0;result=DIERR_INPUTLOST;return true;}
    if(!count||(bytes!=sizeof(DIDEVICEOBJECTDATA)&&bytes!=sizeof(DIDEVICEOBJECTDATA_DX3))||(flags&~DIGDD_PEEK)){
        result=original(bytes,output,count,flags);
        Guard lock;policy.unsupported(key);policy.finish(ticket,false,false,(flags&DIGDD_PEEK)!=0,false);return true;
    }
    bool safe=false;{Guard lock;safe=policy.safe_relative(key);}
    if(!safe){result=DIERR_INPUTLOST;*count=0;Guard lock;policy.unsupported(key);policy.finish(ticket,false,false,(flags&DIGDD_PEEK)!=0,false);return true;}
    if(ticket.mode==Mode::full){
        result=original(bytes,output,count,flags);
        const bool success=SUCCEEDED(result);if(success)*count=0;
        const bool drained=success&&discard(expected);
        Guard lock;const auto env=sample();policy.tick(env.now,env.valid);policy.finish(ticket,drained,false,(flags&DIGDD_PEEK)!=0,success);return true;
    }
    const DWORD requested=*count;const bool peek=(flags&DIGDD_PEEK)!=0;
    std::array<DIDEVICEOBJECTDATA,Buffer::capacity> incoming{};
    // Physical reads consume into our owned FIFO even for virtual PEEK. This
    // cannot alter the caller-visible axis order, count or repeated PEEK data.
    DWORD queued=INFINITE;
    result=original(static_cast<DWORD>(sizeof(DIDEVICEOBJECTDATA)),nullptr,&queued,DIGDD_PEEK);
    const bool physical_overflow=result==DI_BUFFEROVERFLOW;
    bool queue_too_large=queued>incoming.size();
    {Guard lock;if(auto *buffer=policy.buffer(key))queue_too_large=queue_too_large||queued>buffer->free();}
    if(SUCCEEDED(result)&&queue_too_large){
        {Guard lock;policy.unsupported(key,Reason::buffer_capacity);}
        *count=0;result=DIERR_INPUTLOST;const bool drained=discard(expected);
        Guard lock;policy.finish(ticket,drained,false,peek,true);return true;
    }
    DWORD fetched=queued;
    if(SUCCEEDED(result))result=original(static_cast<DWORD>(sizeof(DIDEVICEOBJECTDATA)),incoming.data(),&fetched,0);
    if(FAILED(result)){
        // Original error/output semantics remain intact. A temporarily lost
        // device revokes ownership rather than delivering an unproven sample.
        Guard lock;policy.finish(ticket,false,false,peek,false);return true;
    }
    bool changed=false,capacity=false,unknown=false;
    {
        Guard lock;const auto env=sample();policy.tick(env.now,env.valid);changed=!policy.current(ticket);
        auto *buffer=policy.buffer(key);
        if(!changed&&buffer){
            if(physical_overflow||result==DI_BUFFEROVERFLOW){buffer->overflow=true;policy.overflow();}
            if(fetched>incoming.size()||fetched>queued)capacity=true;
            else for(DWORD i=0;i<fetched;++i){
                const auto &r=incoming[i];
                if(r.dwOfs==offsetof(DIMOUSESTATE,lX)||r.dwOfs==offsetof(DIMOUSESTATE,lY)||r.dwOfs==offsetof(DIMOUSESTATE,lZ)){
                    if(!buffer->push({r.dwOfs,r.dwData,r.dwTimeStamp,r.dwSequence,r.uAppData}))capacity=true;
                }else if(r.dwOfs>=offsetof(DIMOUSESTATE,rgbButtons)&&r.dwOfs<expected){policy.filtered();}
                else unknown=true;
            }
            if(!capacity&&!unknown){
                const auto available=std::min<std::size_t>(requested,buffer->size());
                if(output)for(std::size_t i=0;i<available;++i){
                    const auto &r=buffer->at(i);const DIDEVICEOBJECTDATA value{r.offset,r.data,r.time,r.sequence,r.app};
                    std::memcpy(reinterpret_cast<BYTE *>(output)+i*bytes,&value,bytes);
                }
                *count=static_cast<DWORD>(available);result=buffer->overflow?DI_BUFFEROVERFLOW:DI_OK;
                if(output)policy.delivered(available);
                if(!peek){buffer->consume(available);buffer->overflow=false;}
                policy.finish(ticket,true,false,peek,false);return true;
            }
            policy.unsupported(key,capacity?Reason::buffer_capacity:Reason::layout);
        }
    }
    // An ownership generation changed while the original method ran, or the
    // bounded queue cannot faithfully retain every axis. Never fabricate or
    // silently truncate movement; revoke, discard and report explicit failure.
    *count=0;result=DIERR_INPUTLOST;const bool drained=discard(expected);
    {Guard lock;policy.finish(ticket,drained,false,peek,true);}
    return true;
}
template<class Drain> bool after_state(std::uintptr_t key,DWORD bytes,LPVOID output,HRESULT original,Drain discard){
    return after_state_with_environment(key,bytes,output,original,discard,environment);
}
template<class Original,class Drain> bool before_data(std::uintptr_t key,DWORD bytes,LPDIDEVICEOBJECTDATA output,LPDWORD count,DWORD flags,HRESULT &result,Original original,Drain discard){
    return before_data_with_environment(key,bytes,output,count,flags,result,original,discard,environment);
}
inline Result api_call(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,Mode mode,Snapshot *out,unsigned operation) {
    if(!out||out->size!=sizeof(Snapshot)||out->version!=api_version||!owned_window(window,false))return Result::bad_argument;
    if(!TryAcquireSRWLockExclusive(&mutex)){revoke_pending.store(true);*out={};out->reason=static_cast<unsigned>(Reason::lock_contention);return Result::busy;}
    if(revoke_pending.exchange(false))policy.invalidate(Reason::lock_contention);
    const auto now=GetTickCount64();const bool valid=owned_window(window,true);policy.tick(now,owned_window(policy.window(),true));
    Result result=Result::ok;
    if(operation==1)result=policy.request(window,token,duration,mode,now,valid);
    else if(operation==2)result=policy.release(window,token);
    *out=policy.snapshot(window,now,valid);ReleaseSRWLockExclusive(&mutex);return result;
}
inline Result MINECOME_SELECTIVE_CALL query(std::uintptr_t window,std::uint64_t token,Snapshot *out){return api_call(window,token,0,Mode::none,out,0);}
inline Result MINECOME_SELECTIVE_CALL request(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,Mode mode,Snapshot *out){return api_call(window,token,duration,mode,out,1);}
inline Result MINECOME_SELECTIVE_CALL release(std::uintptr_t window,std::uint64_t token,Snapshot *out){return api_call(window,token,0,Mode::none,out,2);}
inline const Api api{sizeof(Api),api_version,query,request,release};
}
extern "C" __declspec(dllexport) const minecome::selective::Api *MINECOME_SELECTIVE_CALL MineComeGetSelectiveMouseCaptureApi(std::uint32_t version,std::uint32_t size){
    return version==minecome::selective::api_version&&size==sizeof(minecome::selective::Api)?&minecome::selective::adapter::api:nullptr;
}
// Only cursor recentering/clipping is excepted from ReShade's broad UI block.
// Keyboard/buttons/raw/window-message handling remains its inspected baseline.
bool MineComeSelectiveCursorLook() {
    namespace a=minecome::selective::adapter;namespace m=minecome::selective;
    if(!TryAcquireSRWLockExclusive(&a::mutex))return false;
    if(a::revoke_pending.exchange(false))a::policy.invalidate(m::Reason::lock_contention);
    const auto window=a::policy.window();const bool valid=a::owned_window(window,true);
    const auto snapshot=a::policy.snapshot(window,GetTickCount64(),valid);
    const bool result=valid&&(snapshot.flags&m::active)&&!(snapshot.flags&m::draining)&&snapshot.mode==m::Mode::buttons;
    ReleaseSRWLockExclusive(&a::mutex);return result;
}
