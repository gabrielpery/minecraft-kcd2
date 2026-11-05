#pragma once
#include "gameplay_keyboard_api.hpp"
namespace minecome::gameplay_keyboard {
constexpr bool ui_key(std::uint32_t vk){return (vk>=0x31&&vk<=0x39)||vk==0x45||vk==0x1b;}
constexpr bool ui_scan(std::uint32_t scan){return (scan>=2&&scan<=10)||scan==0x12||scan==1;}
class Policy {
    std::uintptr_t window_=0;std::uint64_t token_=0,expires_=0,last_=0;Mode mode_=Mode::none;
public:
    void clear(){window_=0;token_=0;expires_=0;last_=0;mode_=Mode::none;}
    std::uintptr_t window()const{return window_;}
    bool live(std::uint64_t now,bool owned){if(!owned||now<last_||now>=expires_)clear();else last_=now;return mode_!=Mode::none;}
    bool request(std::uintptr_t window,std::uint64_t token,std::uint32_t ms,Mode mode,std::uint64_t now,bool owned){
        if(!window||!token||!owned||!ms||ms>max_lease_ms||(mode!=Mode::ui&&mode!=Mode::full))return false;
        live(now,owned);
        if(token_&&(token_!=token||window_!=window))return false;
        window_=window;token_=token;expires_=now+ms;last_=now;mode_=mode;return true;
    }
    bool query(std::uintptr_t window,std::uint64_t token,std::uint64_t now,bool owned){
        const bool active=live(now,owned);return owned&&(!token||(active&&window_==window&&token_==token));
    }
    bool release(std::uintptr_t window,std::uint64_t token){if(window_!=window||token_!=token||!token)return false;clear();return true;}
    bool blocks(std::uint32_t vk,std::uint64_t now,bool owned){return live(now,owned)&&(mode_==Mode::full||ui_key(vk));}
    bool blocks_scan(std::uint32_t scan,std::uint64_t now,bool owned){return live(now,owned)&&(mode_==Mode::full||ui_scan(scan));}
};
}
