#pragma once
#include "input_contract.hpp"
#include <array>

namespace minecome::hud::input {
// Chat uses a distinct ACK screen; the frozen HUD schema still renders any
// actual Minecraft screen as 1. No invented third texture screen is accepted.
constexpr std::uint32_t chat_render_screen(std::uint32_t screen) noexcept { return screen==2?1:screen; }
// Keep world UI controls before movement controls. Chat openers are identified
// by their virtual keys, never by an index range that would swallow F5.
inline constexpr std::size_t gameplay_ui_key_count=14;
inline constexpr std::array<std::uint32_t,21> gameplay_capture_keys{
    0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x45,0x1b,0x54,0xbf,0x74,
    0x57,0x41,0x53,0x44,0x20,0x10,0x11};
constexpr bool chat_opener(std::uint32_t key) noexcept {return key==0x54||key==0xbf;}
constexpr bool perspective_key(std::uint32_t key) noexcept {return key==0x74;}
constexpr bool world_one_shot(std::uint32_t key) noexcept {return chat_opener(key)||perspective_key(key);}
constexpr bool perspective_allowed(std::uint32_t format,std::uint32_t screen) noexcept {return format==2&&screen==0;}
using ChatKeyState=std::array<std::uint8_t,256>;
// ReShade v6.8.0 overwrites down 0x88 with released 0x08. A fresh release
// between two continuously eligible up samples proves a missed short press.
// This recovers one plain-key tap, not event ordering or modifier history.
class ReleasedTapGate {
public:
    ChatKeyState update(bool ready,const ChatKeyState &down,const ChatKeyState &released) noexcept {
        ChatKeyState taps{};
        bool modifiers=false;
        for(unsigned key:{0x10u,0x11u,0x12u,0xa0u,0xa1u,0xa2u,0xa3u,0xa4u,0xa5u})
            if(down[key]||released[key]||previous_down_[key]||previous_released_[key])modifiers=true;
        if(ready&&ready_&&!modifiers){
            for(unsigned key=0;key<256;++key)
                if(!down[key]&&!previous_down_[key]&&released[key]&&!previous_released_[key])taps[key]=1;
        }
        previous_down_=down;previous_released_=released;ready_=ready;
        return taps;
    }
private:
    ChatKeyState previous_down_{},previous_released_{};
    bool ready_=false;
};
struct ChatEdges { std::array<bool,256> down{},up{},pulse{}; };
class ChatKeyboard {
public:
    // Observe even while disabled: an opener or key held during a screen/lease
    // handoff must release before it can be interpreted as newly typed text.
    ChatEdges update(bool ready,const ChatKeyState &keys,std::uint64_t now,const ChatKeyState &pulses={}) noexcept {
        ChatEdges edges;
        const bool chord=keys[0x11]||keys[0x12]||keys[0xa2]||keys[0xa3]||keys[0xa4]||keys[0xa5];
        for(unsigned key=0;key<256;++key){
            const bool held=keys[key]!=0;
            if(!ready||chord){next_[key]=0;}
            else if(!held&&!previous_[key]&&pulses[key]){edges.down[key]=edges.pulse[key]=true;next_[key]=0;}
            else if(held&&!previous_[key]){edges.down[key]=true;next_[key]=now+400;}
            else if(held&&next_[key]&&now>=next_[key]&&key!=13&&key!=27){
                edges.down[key]=true;next_[key]=now+50; // No backlog after stalls.
            }
            if(!held){edges.up[key]=forwarded_[key];forwarded_[key]=false;next_[key]=0;}
            // Disabling always releases the chat editor without replay later.
            if(!ready&&forwarded_[key]){edges.up[key]=true;forwarded_[key]=false;}
            previous_[key]=held;
        }
        return edges;
    }
    // Only dispatched downs own a release. A closing Enter/Esc can truncate a
    // sampled batch before its later keys ever reach the ordered ring.
    void forwarded_edit(unsigned key) noexcept { if(key<256&&valid_edit(key))forwarded_[key]=true; }
private:
    std::array<bool,256> previous_{},forwarded_{};
    std::array<std::uint64_t,256> next_{};
};
// Translate only the returned UTF-16 count, rejecting isolated surrogates and
// C0/C1 controls. ToUnicodeEx may place additional non-result units in its buffer.
template<class Sink>
bool chat_utf16(std::span<const std::uint16_t> units,Sink sink) {
    for(std::size_t i=0;i<units.size();++i){
        std::uint32_t scalar=units[i];
        if(scalar>=0xd800&&scalar<=0xdbff){
            if(i+1==units.size()||units[i+1]<0xdc00||units[i+1]>0xdfff)continue;
            scalar=0x10000+((scalar-0xd800)<<10)+(units[++i]-0xdc00);
        }
        if(valid_text(scalar)&&!sink(scalar))return false;
    }
    return true;
}
} // namespace minecome::hud::input
