// Match the upstream Windows.props exclusion that previously hid MK_*.
#define NOKEYSTATES
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include "../reshade/motion_capture_adapter.hpp"
#include <iostream>
static_assert(minecome::motion::held_mouse_buttons==0x0073);
int main(){
    MSG move{};move.hwnd=reinterpret_cast<HWND>(7);move.message=WM_MOUSEMOVE;move.wParam=0x007f;
    if(!minecome::motion::window_move(move,7,true)||move.wParam!=0x000c)return 1;
    minecome::motion::Snapshot snapshot;
    if(!MineComeReadMotionDiagnostics(&snapshot)||snapshot.size!=64)return 1;
    // Instantiate the actual production environment wrapper, not only the
    // injected-clock test path. The device/window is unowned and stays untouched.
    DIMOUSESTATE state{7,9,0,{}};
    if(minecome::motion::adapter::after_state(99,sizeof(state),&state,DI_OK,[](std::uint32_t){return true;})||state.lX!=7||state.lY!=9)return 1;
    std::cout<<"MOTION_SDK_NOKEYSTATES checks=3 PASS\n";
}
