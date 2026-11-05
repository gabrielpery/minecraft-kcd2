#pragma once
#include "mouse_forwarding.hpp"

namespace minecome::hud::input {
// Held world actions use the ordinary bounded input mailbox, never the old
// sixteen-click diagnostic log. Two neutral captured frames precede each entry.
class GameplayWorldButtons {
public:
    PointerBatch update(bool ready,unsigned buttons,std::uint64_t utc) noexcept {
        PointerBatch batch;
        if(!ready||(buttons&~3u)){close(utc,batch);return batch;}
        if(!active_){
            if(buttons){neutral_=0;return batch;}
            if(++neutral_<2)return batch;
            active_=true;
        }
        const auto changed=held_^buttons;
        for(unsigned b=0;b<2;++b)if(changed&(1u<<b))
            batch.add({utc,buttons&(1u<<b)?Kind::world_button_down:Kind::world_button_up,b,0,0,0});
        held_=buttons;return batch;
    }
    void close(std::uint64_t utc,PointerBatch &batch) noexcept {
        for(unsigned b=0;b<2;++b)if(held_&(1u<<b))batch.add({utc,Kind::world_button_up,b,0,0,0});
        held_=neutral_=0;active_=false;
    }
    unsigned held()const noexcept{return held_;}
    bool active()const noexcept{return active_;}
private:
    unsigned held_=0,neutral_=0;bool active_=false;
};
}
