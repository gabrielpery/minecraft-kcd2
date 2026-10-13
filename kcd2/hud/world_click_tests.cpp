#include "world_click.hpp"
#include <iostream>
#include <stdexcept>
#include <string>
namespace world=minecome::hud::world;
int main(){
    unsigned checks=0;auto check=[&](bool value){++checks;if(!value)throw std::runtime_error("world_click_check_"+std::to_string(checks));};
    world::Gate gate;std::uint64_t tick=1000;
    auto update=[&](bool ready,unsigned buttons){++tick;return gate.update(ready,buttons,tick,tick,7);};
    check(update(false,2).sequence==0);check(update(true,2).sequence==0&&!gate.active());
    check(update(true,0).sequence==0&&!gate.active());check(update(true,0).sequence==0&&gate.active());
    auto right=update(true,2);check(right.sequence==1&&right.action==1&&right.ui_sequence==7&&right.utc>1000);
    for(unsigned i=0;i<20;i++)check(update(true,2).sequence==0);
    check(update(true,0).sequence==0);auto left=update(true,1);check(left.sequence==2&&left.action==2);
    // Screen transition and held inventory button cannot become world input.
    check(update(false,1).sequence==0&&!gate.active());check(update(true,1).sequence==0);
    check(update(true,0).sequence==0&&!gate.active());check(update(true,2).sequence==0&&!gate.active());
    check(update(true,0).sequence==0);check(update(true,0).sequence==0&&gate.active());
    check(update(true,2).sequence==3);check(update(true,1).sequence==0&&!gate.active());
    check(update(true,1).sequence==0);check(update(true,0).sequence==0);check(update(true,0).sequence==0&&gate.active());
    gate.suspend();check(!gate.active());check(update(true,0).sequence==0&&!gate.active());check(update(true,0).sequence==0&&gate.active());
    for(std::uint64_t i=4;i<=world::max_clicks;i++){
        const auto click=update(true,2);check(click.sequence==i&&click.action==1);check(update(true,0).sequence==0);
    }
    check(gate.sequence()==16);check(update(true,2).sequence==0&&gate.failure()==world::Gate::Failure::capacity);
    check(update(false,0).sequence==0);check(update(true,0).sequence==0&&gate.failure()==world::Gate::Failure::capacity);
    world::Gate both;check(both.update(true,3,1,1,0).sequence==0&&both.failure()==world::Gate::Failure::simultaneous_buttons);
    check(both.update(true,0,2,2,0).sequence==0&&both.failure()==world::Gate::Failure::simultaneous_buttons);
    world::Gate invalid;check(invalid.update(true,4,1,1,0).sequence==0&&invalid.failure()==world::Gate::Failure::invalid_buttons);
    world::Gate clock;check(clock.update(true,0,1,2,0).sequence==0);check(clock.update(true,0,2,1,0).sequence==0&&clock.failure()==world::Gate::Failure::clock);
    world::Gate no_time;check(no_time.update(true,0,0,1,0).sequence==0&&no_time.failure()==world::Gate::Failure::clock);
    world::Queue queue;world::Click record;check(!queue.pop(record));
    for(std::uint64_t i=1;i<=16;i++)check(queue.push({i,1000,7,1}));
    check(!queue.push({17,1000,7,1})&&queue.overflowed());
    for(std::uint64_t i=1;i<=16;i++)check(queue.pop(record)&&record.sequence==i&&record.utc==1000&&record.ui_sequence==7&&record.action==1);
    check(!queue.pop(record));check(queue.push({1,1001,8,2}));check(queue.pop(record)&&record.ui_sequence==8&&record.action==2);
    const world::Click valid{1,1000,7,1};
    check(world::delivery(valid,true,1000,7,0)==world::Delivery::emit);
    check(world::delivery(valid,true,1250,7,0)==world::Delivery::emit);
    check(world::delivery(valid,true,1251,7,0)==world::Delivery::drop);
    check(world::delivery(valid,true,999,7,0)==world::Delivery::drop);
    check(world::delivery(valid,true,1000,6,0)==world::Delivery::wait);
    check(world::delivery(valid,true,1251,6,0)==world::Delivery::drop);
    check(world::delivery(valid,false,1000,7,0)==world::Delivery::drop);
    check(world::delivery(valid,true,1000,7,1)==world::Delivery::drop);
    for(const auto bad: {world::Click{},world::Click{17,1000,7,1},world::Click{1,1000,7,0},world::Click{1,1000,7,3}})
        check(world::delivery(bad,true,1000,7,0)==world::Delivery::drop);
    const world::Click owned{1,1000,7,1,123,456,789};
    check(world::capture_matches(owned,true,456,789));
    check(!world::capture_matches(owned,false,456,789));
    check(!world::capture_matches(owned,true,457,789));
    check(!world::capture_matches(owned,true,456,790));
    check(!world::capture_matches(valid,true,0,0));
    for(auto field=0;field<3;field++){
        auto missing=owned;if(field==0)missing.window=0;else if(field==1)missing.token=0;else missing.generation=0;
        check(!world::capture_matches(missing,true,missing.token,missing.generation));
    }
    std::cout<<"WORLD_CLICK_TEST_PASS checks="<<checks<<" no_game=true\n";
}
