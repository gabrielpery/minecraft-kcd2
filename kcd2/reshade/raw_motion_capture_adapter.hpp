#pragma once
// R3 preserves frozen capture API2 and motion diagnostics API1. Its only new
// exception is a mouse helper route witnessed by upstream message resolution.
#include "motion_capture_adapter.hpp"
#include "raw_motion_diagnostics_api.hpp"
#include "raw_motion_policy.hpp"
namespace minecome::raw_motion::adapter {
struct Counters {
    std::atomic<std::uint64_t> mouse_raw_packets_seen{0},registered_helper_candidates{0},helper_moves_passed{0},
        route_owner_rejected{0},packet_rejected{0};
};
inline Counters counters;
inline void increment(std::atomic<std::uint64_t> &value) noexcept {value.fetch_add(1,std::memory_order_relaxed);}
template<class OwnedWindow,class OwnedButtons> bool route(const MSG &message,const RAWINPUT &raw,std::size_t received,
    std::uintptr_t resolved_owner,bool registered_mouse,OwnedWindow owned_window,OwnedButtons owned_buttons) {
    if(raw.header.dwType!=RIM_TYPEMOUSE||received<sizeof(RAWINPUTHEADER))return false;
    increment(counters.mouse_raw_packets_seen);
    // Main render-window packets retain the frozen R2 handling/counters. This
    // separate path never widens its strict original-HWND predicate.
    const auto helper=reinterpret_cast<std::uintptr_t>(message.hwnd);
    if(helper==resolved_owner)return false;
    if(registered_mouse)increment(counters.registered_helper_candidates);
    if(!registered_mouse||!owned_window(helper)||!resolved_owner){increment(counters.route_owner_rejected);return false;}
    if(!routed_message(message,raw,received,resolved_owner,true,true)){increment(counters.packet_rejected);return false;}
    const bool passed=owned_buttons(resolved_owner,[&](auto owner){return owner==resolved_owner&&owned_window(helper);});
    if(passed){increment(counters.helper_moves_passed);minecome::motion::adapter::increment(minecome::motion::adapter::counters.raw_moves_passed);}
    else increment(counters.route_owner_rejected);
    return passed;
}
}
// Called only after upstream observed the genuine mouse packet and selected
// its input object. The caller supplies the registration witness sampled under
// the same window-map lock and keeps that lock until this function returns;
// no independent alias or most-rendered heuristic is
// used here. Neither the message nor its opaque raw-input packet is rewritten.
bool MineComeAllowRoutedRawMotion(const MSG *message,HWND resolved_owner,bool registered_mouse) {
    if(!message||message->message!=WM_INPUT)return false;
    RAWINPUT raw{};UINT bytes=sizeof(raw);
    const auto received=GetRawInputData(reinterpret_cast<HRAWINPUT>(message->lParam),RID_INPUT,&raw,&bytes,sizeof(RAWINPUTHEADER));
    if(received==UINT(-1))return false;
    return minecome::raw_motion::adapter::route(*message,raw,received,reinterpret_cast<std::uintptr_t>(resolved_owner),registered_mouse,
        [](auto helper){return minecome::selective::adapter::owned_window(helper,false);},
        [](auto owner,auto apply){return minecome::motion::adapter::owned_buttons(owner,apply);});
}
extern "C" __declspec(dllexport) bool MINECOME_RAW_MOTION_CALL MineComeReadRawMotionDiagnostics(minecome::raw_motion::Snapshot *out) {
    namespace m=minecome::raw_motion;namespace a=m::adapter;
    if(!out||out->size!=sizeof(m::Snapshot)||out->version!=m::api_version)return false;
    m::Snapshot snapshot;
    snapshot.mouse_raw_packets_seen=a::counters.mouse_raw_packets_seen.load(std::memory_order_relaxed);
    snapshot.registered_helper_candidates=a::counters.registered_helper_candidates.load(std::memory_order_relaxed);
    snapshot.helper_moves_passed=a::counters.helper_moves_passed.load(std::memory_order_relaxed);
    snapshot.route_owner_rejected=a::counters.route_owner_rejected.load(std::memory_order_relaxed);
    snapshot.packet_rejected=a::counters.packet_rejected.load(std::memory_order_relaxed);
    *out=snapshot;return true;
}
