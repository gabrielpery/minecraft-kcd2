#pragma once
#include <array>
#include <cstdint>
namespace minecome::hud::input {
inline constexpr std::array<std::uint32_t,5> movement_keys{0x57,0x41,0x53,0x44,0x20};
struct MovementEdges { std::uint32_t up=0,down=0; };
// Only observed world-screen controls can own guest movement. A screen change,
// pending capture drain or observation gap releases holds; two physically
// neutral frames are required before a later press can start again.
class MovementGate {
public:
    MovementEdges update(bool world_ready,std::uint32_t physical) noexcept {
        physical&=31u;
        if(!world_ready){
            MovementEdges result{held_,0};held_=0;neutral_=0;armed_=false;return result;
        }
        if(!armed_){
            if(physical){neutral_=0;return {};}
            if(++neutral_>=2)armed_=true;
            return {};
        }
        const MovementEdges result{held_&~physical,physical&~held_};
        held_=physical;return result;
    }
    std::uint32_t held() const noexcept {return held_;}
    bool armed() const noexcept {return armed_;}
private:
    std::uint32_t held_=0;unsigned neutral_=0;bool armed_=false;
};
}
