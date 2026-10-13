#pragma once
#include <Windows.h>
#include <cstddef>
#include <cstdint>
namespace minecome::motion {
// Inspected 2026-10-13: Microsoft WM_MOUSEMOVE and RAWMOUSE SDK contracts.
// https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousemove
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawmouse
// Pinned ReShade deps/Windows.props defines NOKEYSTATES, hiding the MK_*
// macros. These SDK WinUser.h values are respectively L/R/M/X1/X2; using the
// documented message bits keeps the upstream compile target unchanged.
constexpr WPARAM held_mouse_buttons=0x0001u|0x0002u|0x0010u|0x0020u|0x0040u;
inline bool window_move(MSG &message,std::uintptr_t owner,bool settled_buttons) noexcept {
    if(!settled_buttons||message.message!=WM_MOUSEMOVE||!owner||reinterpret_cast<std::uintptr_t>(message.hwnd)!=owner)return false;
    message.wParam&=~held_mouse_buttons;return true;
}
// SDK RAWINPUT/RAWMOUSE contracts: only pure relative XY packets are passed.
// The original HRAWINPUT remains immutable. Editing this local packet would
// not protect the host's later GetRawInputData read, so mixed packets stay blocked.
inline bool pure_relative_xy(const RAWINPUT &raw,std::size_t received) noexcept {
    if(received<sizeof(RAWINPUTHEADER)||raw.header.dwType!=RIM_TYPEMOUSE||
       raw.header.dwSize!=sizeof(RAWINPUTHEADER)+sizeof(RAWMOUSE)||received<raw.header.dwSize||
       !raw.header.hDevice||raw.header.wParam!=RIM_INPUT)return false;
    const auto &mouse=raw.data.mouse;
    return (mouse.usFlags&~MOUSE_MOVE_NOCOALESCE)==0&&mouse.usButtonFlags==0&&mouse.usButtonData==0&&
        mouse.ulRawButtons==0&&(mouse.lLastX!=0||mouse.lLastY!=0);
}
inline bool raw_message(const MSG &message,const RAWINPUT &raw,std::size_t received,
                        std::uintptr_t owner,bool settled_buttons) noexcept {
    return settled_buttons&&owner&&reinterpret_cast<std::uintptr_t>(message.hwnd)==owner&&message.message==WM_INPUT&&
        GET_RAWINPUT_CODE_WPARAM(message.wParam)==RIM_INPUT&&pure_relative_xy(raw,received);
}
}
