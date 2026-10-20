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
    auto leased=owned;leased.lease_deadline=2100;
    auto decide=[&](world::Capture capture,std::uint64_t steady=2001,std::uint64_t utc=1001,bool live=true,std::uint64_t ack=7,unsigned screen=0){
        return world::delivery_with_capture(leased,live,utc,steady,ack,screen,capture);
    };
    check(decide(world::Capture::busy).outcome==world::Delivery::wait);
    check(decide(world::Capture::busy).reason==world::DeliveryReason::capture_busy);
    check(decide(world::Capture::busy,2099,1099).outcome==world::Delivery::wait);
    check(leased.lease_deadline==2100&&leased.utc==1000&&leased.sequence==1);
    check(decide(world::Capture::matched,2099,1099).outcome==world::Delivery::emit);
    for(auto capture:{world::Capture::matched,world::Capture::busy,world::Capture::unavailable}){
        check(decide(capture,2100,1100).outcome==world::Delivery::drop);
        check(decide(capture,2100,1100).reason==world::DeliveryReason::capture_deadline);
        check(decide(capture,2001,1001,false).reason==world::DeliveryReason::not_live);
        check(decide(capture,2001,1001,true,7,1).reason==world::DeliveryReason::screen);
        check(decide(capture,2001,999).reason==world::DeliveryReason::clock);
        check(decide(capture,2001,1251).reason==world::DeliveryReason::click_stale);
    }
    check(decide(world::Capture::unavailable).reason==world::DeliveryReason::capture_mismatch);
    check(decide(world::Capture::matched,2001,1001,true,6).reason==world::DeliveryReason::ack_pending);
    check(decide(world::Capture::busy,2001,1001,true,6).reason==world::DeliveryReason::capture_busy);
    check(decide(world::Capture::matched,2100,1100,true,6).outcome==world::Delivery::drop);
    leased.lease_deadline=0;check(decide(world::Capture::busy).reason==world::DeliveryReason::capture_deadline);
    leased=owned;leased.lease_deadline=2100;leased.sequence=0;
    check(decide(world::Capture::busy).reason==world::DeliveryReason::invalid_click);
    // New owner/generation can never turn a deferred physical click into an emit.
    leased=owned;leased.lease_deadline=2100;
    for(auto actual:{world::capture_matches(leased,true,457,789),world::capture_matches(leased,true,456,790),world::capture_matches(leased,false,456,789)})
        check(decide(actual?world::Capture::matched:world::Capture::unavailable).outcome==world::Delivery::drop);
    std::cout<<"WORLD_CLICK_TEST_PASS checks="<<checks<<" no_game=true\n";
}
