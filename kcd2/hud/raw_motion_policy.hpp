#pragma once
#include "motion_policy.hpp"
namespace minecome::raw_motion {
// One process-wide target per raw-input usage class. An implicit foreground
// target is not a helper-window witness. Only successful mouse registrations
// participate; keyboard registration cannot confer mouse routing authority.
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawinputdevice
// Inspected 2026-10-13; the caller serializes this small value with its window map.
class Registration {
    std::uintptr_t target_=0;
public:
    void observe(bool success,unsigned page,unsigned usage,unsigned flags,std::uintptr_t target) noexcept {
        if(!success||page!=1)return;
        // A page-wide rule may supersede the explicit mouse target. Do not
        // infer its inclusion/exclusion effects or retain an older witness.
        if(usage==0){target_=0;return;}
        if(usage!=2)return;
        constexpr unsigned known=RIDEV_REMOVE|RIDEV_NOLEGACY|RIDEV_INPUTSINK|RIDEV_CAPTUREMOUSE|RIDEV_EXINPUTSINK|RIDEV_DEVNOTIFY;
        const auto page_bits=flags&(RIDEV_PAGEONLY|RIDEV_EXCLUDE);
        const bool excluded=page_bits&&page_bits!=RIDEV_NOLEGACY;
        target_=(flags&RIDEV_REMOVE)||excluded||(flags&~known)?0:target;
    }
    bool matches(std::uintptr_t window) const noexcept {return window&&window==target_;}
};
inline bool routed_message(const MSG &message,const RAWINPUT &raw,std::size_t received,
    std::uintptr_t resolved_owner,bool registered_mouse,bool helper_owned) noexcept {
    return registered_mouse&&helper_owned&&resolved_owner&&message.hwnd&&
        reinterpret_cast<std::uintptr_t>(message.hwnd)!=resolved_owner&&
        message.message==WM_INPUT&&message.wParam==RIM_INPUT&&
        minecome::motion::pure_relative_xy(raw,received);
}
}
