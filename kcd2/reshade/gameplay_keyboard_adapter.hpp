#pragma once
// Original v5 keyboard adapter, included only by the separate gameplay proxy.
// Hooks keep ReShade's original observations; suppression is on host delivery.
#include "gameplay_keyboard_policy.hpp"
#include <array>
#include <cstring>
namespace minecome::gameplay_keyboard::adapter {
inline SRWLOCK mutex=SRWLOCK_INIT;
inline Policy policy;
struct Device{std::uintptr_t key=0,window=0;bool canonical=false;};
inline std::array<Device,16> devices{};
inline bool capacity_failed=false;
struct Guard{Guard(){AcquireSRWLockExclusive(&mutex);}~Guard(){ReleaseSRWLockExclusive(&mutex);}};
inline bool owned_window(std::uintptr_t value){DWORD pid=0;const auto w=reinterpret_cast<HWND>(value);return w&&IsWindow(w)&&GetWindowThreadProcessId(w,&pid)&&pid==GetCurrentProcessId()&&IsWindowVisible(w)&&!IsIconic(w)&&GetForegroundWindow()==w;}
inline bool devices_ready(std::uintptr_t window){if(capacity_failed)return false;for(const auto &d:devices)if(d.key&&(!d.canonical||d.window!=window))return false;return true;}
inline bool owned(){return owned_window(policy.window())&&devices_ready(policy.window());}
inline void add(std::uintptr_t key){Guard g;for(auto &d:devices)if(d.key==key)return;for(auto &d:devices)if(!d.key){d.key=key;policy.clear();return;}capacity_failed=true;policy.clear();}
inline void remove(std::uintptr_t key){Guard g;for(auto &d:devices)if(d.key==key){d={};policy.clear();}}
inline bool canonical(LPCDIDATAFORMAT f){
    if(!f||f->dwSize!=sizeof(*f)||f->dwObjSize!=sizeof(DIOBJECTDATAFORMAT)||f->dwDataSize!=256||f->dwNumObjs!=256||!f->rgodf)return false;
    std::array<bool,256> seen{};
    for(unsigned i=0;i<256;++i){const auto &o=f->rgodf[i];const auto type=DIDFT_GETTYPE(o.dwType);const auto key=DIDFT_GETINSTANCE(o.dwType);
        if(key>=256||o.dwOfs!=key||seen[key]||o.dwFlags||!o.pguid||*o.pguid!=GUID_Key||(type!=DIDFT_BUTTON&&type!=DIDFT_PSHBUTTON))return false;seen[key]=true;}
    return true;
}
inline void format(std::uintptr_t key,LPCDIDATAFORMAT f){Guard g;policy.clear();for(auto &d:devices)if(d.key==key)d.canonical=canonical(f);}
inline void cooperative(std::uintptr_t key,HWND window){Guard g;policy.clear();for(auto &d:devices)if(d.key==key)d.window=reinterpret_cast<std::uintptr_t>(window);}
inline bool MINECOME_GAMEPLAY_CALL query(std::uintptr_t window,std::uint64_t token){Guard g;return devices_ready(window)&&policy.query(window,token,GetTickCount64(),owned_window(window));}
inline bool MINECOME_GAMEPLAY_CALL request(std::uintptr_t window,std::uint64_t token,std::uint32_t ms,Mode mode){Guard g;return devices_ready(window)&&policy.request(window,token,ms,mode,GetTickCount64(),owned_window(window));}
inline bool MINECOME_GAMEPLAY_CALL release(std::uintptr_t window,std::uint64_t token){Guard g;return policy.release(window,token);}
inline bool blocked(std::uint32_t vk){Guard g;return policy.blocks(vk,GetTickCount64(),owned());}
inline bool active(){Guard g;return policy.live(GetTickCount64(),owned());}
template<class Blocked> void filter_state(DWORD bytes,void *output,Blocked is_blocked){
    if(!output||bytes!=256)return;for(unsigned i=0;i<256;++i)if(is_blocked(i))static_cast<BYTE *>(output)[i]=0;
}
template<class Blocked> void filter_data(DWORD bytes,LPDIDEVICEOBJECTDATA records,DWORD count,Blocked is_blocked){
    if(!records||(bytes!=sizeof(DIDEVICEOBJECTDATA)&&bytes!=sizeof(DIDEVICEOBJECTDATA_DX3)))return;
    // Preserve count/order, including PEEK: suppressed records become releases,
    // so a suppressed prefix cannot starve following walking keys or the FIFO.
    for(DWORD i=0;i<count;++i){auto *r=reinterpret_cast<BYTE *>(records)+i*bytes;DWORD scan=0;std::memcpy(&scan,r,sizeof(scan));if(is_blocked(scan)){const DWORD up=0;std::memcpy(r+sizeof(DWORD),&up,sizeof(up));}}
}
inline void state(DWORD bytes,void *output){Guard g;const auto now=GetTickCount64();if(!policy.live(now,owned()))return;filter_state(bytes,output,[&](unsigned scan){return policy.blocks_scan(scan,now,true);});}
inline void data(DWORD bytes,LPDIDEVICEOBJECTDATA records,DWORD count){Guard g;const auto now=GetTickCount64();if(!policy.live(now,owned()))return;filter_data(bytes,records,count,[&](unsigned scan){return policy.blocks_scan(scan,now,true);});}
inline const Api api{sizeof(Api),api_version,query,request,release};
}
