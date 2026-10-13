#pragma once
// Original MineCome adapter, compiled in the pinned ReShade dinput8.cpp hook
// chain. Windows SDK dinput.h defines the interface slots and data contracts.
#include "mouse_capture_policy.hpp"
#include <atomic>
#include <cstring>

namespace minecome::mouse::adapter {
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
// Both state and buffered queues must be consumed before ownership is returned.
// Drain functions are original hook-chain calls supplied by the current device
// callback; they are never cached or invoked by the rendering/API thread.
template<class State,class Data> bool drain(std::uint32_t bytes,State state,Data data) {
    if(bytes!=sizeof(DIMOUSESTATE)&&bytes!=sizeof(DIMOUSESTATE2))return false;
    DIMOUSESTATE2 discarded{};
    if(FAILED(state(bytes,&discarded)))return false;
    DWORD count=INFINITE;const auto hr=data(sizeof(DIDEVICEOBJECTDATA),nullptr,&count,0);
    return SUCCEEDED(hr)||hr==DIERR_NOTBUFFERED;
}
template<class Drain> bool after_state(std::uintptr_t key,DWORD bytes,LPVOID output,HRESULT original,Drain discard) {
    if(FAILED(original))return false;
    Policy::Ticket ticket;std::uint32_t expected=0;
    {Guard lock;ticket=policy.begin(key,GetTickCount64(),owned_window(policy.window(),true));expected=policy.bytes(key);
        if(ticket.suppress&&(!policy.safe_relative(key)||!output||bytes!=expected)){policy.unsupported(key);return false;}}
    if(!ticket.suppress)return false;
    std::memset(output,0,bytes);
    const bool drained=discard(expected);
    {Guard lock;policy.tick(GetTickCount64(),owned_window(policy.window(),true));policy.finish(ticket,drained,true,false);}
    return true;
}
template<class Drain> bool after_data(std::uintptr_t key,DWORD bytes,LPDWORD count,DWORD flags,HRESULT original,Drain discard) {
    if(FAILED(original))return false;
    Policy::Ticket ticket;std::uint32_t expected=0;
    {Guard lock;ticket=policy.begin(key,GetTickCount64(),owned_window(policy.window(),true));expected=policy.bytes(key);
        if(ticket.suppress&&(!policy.safe_relative(key)||!count||(bytes!=sizeof(DIDEVICEOBJECTDATA)&&bytes!=sizeof(DIDEVICEOBJECTDATA_DX3))||(flags&~DIGDD_PEEK))){policy.unsupported(key);return false;}}
    if(!ticket.suppress)return false;
    *count=0;const bool drained=discard(expected);
    {Guard lock;policy.tick(GetTickCount64(),owned_window(policy.window(),true));policy.finish(ticket,drained,false,(flags&DIGDD_PEEK)!=0);}
    return true;
}
inline Result api_call(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,Snapshot *out,unsigned operation) {
    if(!out||out->size!=sizeof(Snapshot)||out->version!=api_version||!owned_window(window,false))return Result::bad_argument;
    if(!TryAcquireSRWLockExclusive(&mutex)) {revoke_pending.store(true);*out={};out->reason=static_cast<std::uint32_t>(Reason::lock_contention);return Result::busy;}
    if(revoke_pending.exchange(false))policy.invalidate(Reason::lock_contention);
    const auto now=GetTickCount64();const bool valid=owned_window(window,true);
    policy.tick(now,owned_window(policy.window(),true));
    Result result=Result::ok;
    if(operation==1)result=policy.request(window,token,duration,now,valid);
    else if(operation==2)result=policy.release(window,token);
    *out=policy.snapshot(window,now,valid);ReleaseSRWLockExclusive(&mutex);return result;
}
inline Result MINECOME_MOUSE_CALL query(std::uintptr_t window,std::uint64_t token,Snapshot *out){return api_call(window,token,0,out,0);}
inline Result MINECOME_MOUSE_CALL request(std::uintptr_t window,std::uint64_t token,std::uint32_t duration,Snapshot *out){return api_call(window,token,duration,out,1);}
inline Result MINECOME_MOUSE_CALL release(std::uintptr_t window,std::uint64_t token,Snapshot *out){return api_call(window,token,0,out,2);}
inline const Api api{sizeof(Api),api_version,query,request,release};
} // namespace minecome::mouse::adapter

extern "C" __declspec(dllexport) const minecome::mouse::Api *MINECOME_MOUSE_CALL MineComeGetMouseCaptureApi(std::uint32_t version,std::uint32_t size) {
    return version==minecome::mouse::api_version&&size==sizeof(minecome::mouse::Api)?&minecome::mouse::adapter::api:nullptr;
}
