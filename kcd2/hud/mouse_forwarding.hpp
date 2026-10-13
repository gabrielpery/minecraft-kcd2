#pragma once
// Original host-side UI event policy. No OS injection or inventory mechanics.
#include "input_contract.hpp"
#include "hud_contract.hpp"
#include <algorithm>
#include <cmath>

namespace minecome::hud::input {
struct PointerPoint { float x=0,y=0; bool inside=false,valid=false; };
inline PointerPoint pointer_point(float client_x,float client_y,float width,float height,const hud::Rect &rect) noexcept {
    if(!std::isfinite(client_x)||!std::isfinite(client_y)||!std::isfinite(width)||!std::isfinite(height)||
       !std::isfinite(rect.x)||!std::isfinite(rect.y)||!std::isfinite(rect.width)||!std::isfinite(rect.height)||
       width<=0||height<=0||rect.width<=0||rect.height<=0)return {};
    const float x=(client_x/width-rect.x)/rect.width,y=(client_y/height-rect.y)/rect.height;
    return {std::clamp(x,0.0f,1.0f),std::clamp(y,0.0f,1.0f),x>=0&&y>=0&&x<1&&y<1,true};
}
struct PointerBatch {
    std::array<Event,6> events{};std::size_t count=0;
    void add(Event event) noexcept {if(count<events.size())events[count++]=event;}
};
class PointerForwarder {
public:
    // New screens must observe two neutral captured frames. A held button at
    // entry cannot become an accidental click, including after close/reopen.
    PointerBatch update(bool inventory,bool capture_ready,unsigned buttons,PointerPoint point,int wheel,std::uint64_t utc) noexcept {
        PointerBatch batch;
        if(!inventory||!capture_ready||!point.valid){close(utc,batch);return batch;}
        if(!active_){
            if(buttons||wheel){neutral_=0;return batch;}
            if(++neutral_<2)return batch;
            active_=true;known_=false;
        }
        buttons&=3;
        if(!point.inside&&!held_){ // Ignore outside-canvas presses until released.
            if(buttons){active_=false;neutral_=0;}return batch;
        }
        if(!known_||point.x!=x_||point.y!=y_){
            x_=point.x;y_=point.y;known_=true;
            batch.add({utc,Kind::move,0,x_,y_,0});
        }
        const auto changed=buttons^held_;
        for(unsigned button=0;button<2;++button)if(changed&(1u<<button))
            batch.add({utc,buttons&(1u<<button)?Kind::button_down:Kind::button_up,button,x_,y_,0});
        held_=buttons;
        if(wheel&&point.inside)batch.add({utc,Kind::wheel,0,x_,y_,std::clamp(wheel,-16,16)});
        return batch;
    }
    void close(std::uint64_t utc,PointerBatch &batch) noexcept {
        for(unsigned button=0;button<2;++button)if(held_&(1u<<button))batch.add({utc,Kind::button_up,button,x_,y_,0});
        held_=0;neutral_=0;active_=false;known_=false;
    }
    bool active()const noexcept{return active_;}
    unsigned held()const noexcept{return held_;}
private:
    float x_=0.5f,y_=0.5f;unsigned held_=0,neutral_=0;bool active_=false,known_=false;
};
} // namespace minecome::hud::input
