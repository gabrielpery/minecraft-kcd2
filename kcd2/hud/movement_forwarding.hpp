#pragma once
#include <array>
#include <cstdint>
namespace minecome::hud::input {
inline constexpr std::array<std::uint32_t,5> movement_keys{0x57,0x41,0x53,0x44,0x20};
inline constexpr std::array<std::uint32_t,7> flight_movement_keys{0x57,0x41,0x53,0x44,0x20,0x10,0x11};
struct MovementEdges { std::uint32_t up=0,down=0,pulse=0; };
// Only observed world-screen controls can own guest movement. A screen change,
// pending capture drain or observation gap releases holds; two physically
// neutral frames are required before a later press can start again.
class MovementGate {
public:
    explicit MovementGate(std::uint32_t mask=31u) noexcept :mask_(mask&127u){}
    MovementEdges update(bool world_ready,std::uint32_t physical,std::uint32_t pulses=0) noexcept {
        physical&=mask_;
        if(!world_ready){
            MovementEdges result{held_,0};held_=0;neutral_=0;armed_=false;return result;
        }
        if(!armed_){
            if(physical){neutral_=0;return {};}
            if(++neutral_>=2)armed_=true;
            return {};
        }
        // A recovered tap never acquires a held lease. Down/up remain ordered
        // in the ring; the Minecraft client consumes jump edges on tick boundaries.
        const MovementEdges result{held_&~physical,physical&~held_,pulses&mask_&~held_&~physical};
        held_=physical;return result;
    }
    std::uint32_t held() const noexcept {return held_;}
    bool armed() const noexcept {return armed_;}
private:
    std::uint32_t mask_;
    std::uint32_t held_=0;unsigned neutral_=0;bool armed_=false;
};
}
