#pragma once
// R2 wraps the frozen API-v2 adapter; no capture ABI or v2 behavior is changed.
#include "selective_capture_adapter.hpp"
#include "motion_diagnostics_api.hpp"
#include "motion_policy.hpp"
namespace minecome::motion::adapter {
struct Counters {
    std::atomic<std::uint64_t> state_xy_observed{0},state_xy_passed{0},window_moves_passed{0},raw_moves_passed{0},
        raw_mixed_blocked{0},raw_buffer_blocked{0},hook_motion_blocked{0};
};
static_assert(std::atomic<std::uint64_t>::is_always_lock_free);
inline Counters counters;
inline void increment(std::atomic<std::uint64_t> &value) noexcept {value.fetch_add(1,std::memory_order_relaxed);}
template<class Apply> bool owned_buttons(std::uintptr_t target,Apply apply) {
    namespace a=minecome::selective::adapter;namespace s=minecome::selective;
    if(!TryAcquireSRWLockExclusive(&a::mutex))return false;
    if(a::revoke_pending.exchange(false))a::policy.invalidate(s::Reason::lock_contention);
    const auto owner=a::policy.window();const bool valid=a::owned_window(owner,true);
    const auto snapshot=a::policy.snapshot(owner,GetTickCount64(),valid);
    const bool eligible=target==owner&&valid&&(snapshot.flags&s::active)&&!(snapshot.flags&s::draining)&&snapshot.mode==s::Mode::buttons;
    const bool result=eligible&&apply(owner);
    ReleaseSRWLockExclusive(&a::mutex);return result;
}
inline bool has_xy(DWORD bytes,LPVOID output,HRESULT result) noexcept {
    if(FAILED(result)||!output||(bytes!=sizeof(DIMOUSESTATE)&&bytes!=sizeof(DIMOUSESTATE2)))return false;
    LONG xy[2]{};std::memcpy(xy,output,sizeof(xy));return xy[0]!=0||xy[1]!=0;
}
template<class Drain,class Sample> bool after_state_with_environment(std::uintptr_t key,DWORD bytes,LPVOID output,HRESULT result,Drain discard,Sample sample) {
    const bool observed=has_xy(bytes,output,result);
    const bool handled=minecome::selective::adapter::after_state_with_environment(key,bytes,output,result,discard,sample);
    if(handled){if(observed)increment(counters.state_xy_observed);if(has_xy(bytes,output,result))increment(counters.state_xy_passed);}
    return handled;
}
template<class Drain> bool after_state(std::uintptr_t key,DWORD bytes,LPVOID output,HRESULT result,Drain discard){
    return minecome::motion::adapter::after_state_with_environment(key,bytes,output,result,discard,minecome::selective::adapter::environment);
}
}
// Called only after ReShade has recorded the original message and would block it.
// Only exact owned client-window motion can change the caller-visible message.
bool MineComeAllowMotionMessage(MSG *message) {
    if(!message)return false;
    namespace a=minecome::motion::adapter;
    if(message->message==WM_MOUSEMOVE)return a::owned_buttons(reinterpret_cast<std::uintptr_t>(message->hwnd),[&](auto owner){
        const bool allowed=minecome::motion::window_move(*message,owner,true);
        if(allowed)a::increment(a::counters.window_moves_passed);return allowed;
    });
    if(message->message!=WM_INPUT||GET_RAWINPUT_CODE_WPARAM(message->wParam)!=RIM_INPUT)return false;
    // A successful data query returns bytes read; the opaque handle is not
    // replaced, and the game may read the same pure-motion packet afterward.
    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getrawinputdata
    RAWINPUT raw{};UINT bytes=sizeof(raw);
    const auto received=GetRawInputData(reinterpret_cast<HRAWINPUT>(message->lParam),RID_INPUT,&raw,&bytes,sizeof(RAWINPUTHEADER));
    if(received==UINT(-1)||received<sizeof(RAWINPUTHEADER)||raw.header.dwType!=RIM_TYPEMOUSE)return false;
    return a::owned_buttons(reinterpret_cast<std::uintptr_t>(message->hwnd),[&](auto owner){
        const bool allowed=minecome::motion::raw_message(*message,raw,received,owner,true);
        a::increment(allowed?a::counters.raw_moves_passed:a::counters.raw_mixed_blocked);return allowed;
    });
}
bool MineComeAllowMotionPost(HWND window,WPARAM *keys) {
    if(!keys)return false;
    MSG message{};message.hwnd=window;message.message=WM_MOUSEMOVE;message.wParam=*keys;
    if(!MineComeAllowMotionMessage(&message))return false;
    *keys=message.wParam;return true;
}
void MineComeObserveBlockedRawMouse(){minecome::motion::adapter::increment(minecome::motion::adapter::counters.raw_buffer_blocked);}
void MineComeObserveBlockedHookMotion(){minecome::motion::adapter::increment(minecome::motion::adapter::counters.hook_motion_blocked);}
extern "C" __declspec(dllexport) bool MINECOME_MOTION_CALL MineComeReadMotionDiagnostics(minecome::motion::Snapshot *out) {
    namespace a=minecome::motion::adapter;namespace m=minecome::motion;
    if(!out||out->size!=sizeof(m::Snapshot)||out->version!=m::api_version)return false;
    m::Snapshot snapshot;
    snapshot.state_xy_observed=a::counters.state_xy_observed.load(std::memory_order_relaxed);
    snapshot.state_xy_passed=a::counters.state_xy_passed.load(std::memory_order_relaxed);
    snapshot.window_moves_passed=a::counters.window_moves_passed.load(std::memory_order_relaxed);
    snapshot.raw_moves_passed=a::counters.raw_moves_passed.load(std::memory_order_relaxed);
    snapshot.raw_mixed_blocked=a::counters.raw_mixed_blocked.load(std::memory_order_relaxed);
    snapshot.raw_buffer_blocked=a::counters.raw_buffer_blocked.load(std::memory_order_relaxed);
    snapshot.hook_motion_blocked=a::counters.hook_motion_blocked.load(std::memory_order_relaxed);
    *out=snapshot;return true;
}
