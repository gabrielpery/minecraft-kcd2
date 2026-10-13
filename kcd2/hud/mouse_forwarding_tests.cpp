#include "mouse_forwarding.hpp"
#include "mouse_diagnostics.hpp"
#include <iostream>
#include <limits>
#include <stdexcept>
namespace ui=minecome::hud::input;
int main(){
    unsigned checks=0;auto check=[&](bool value){++checks;if(!value)throw std::runtime_error("mouse_forwarding_check_"+std::to_string(checks));};
    const auto rect=minecome::hud::fit_rect(1280,720,1920,1200);
    auto p=ui::pointer_point(960,600,1920,1200,rect);check(p.valid&&p.inside&&std::abs(p.x-0.5f)<0.00001&&std::abs(p.y-0.5f)<0.00001);
    auto outside=ui::pointer_point(960,0,1920,1200,rect);check(outside.valid&&!outside.inside&&outside.y==0);
    check(!ui::pointer_point(1,1,0,1,rect).valid);check(!ui::pointer_point(std::numeric_limits<float>::quiet_NaN(),1,1,1,rect).valid);
    ui::PointerForwarder pointer;const std::uint64_t utc=1000;
    check(pointer.update(true,true,1,p,0,utc).count==0);check(!pointer.active());
    check(pointer.update(true,true,0,p,0,utc).count==0);
    auto batch=pointer.update(true,true,0,p,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::move&&pointer.active());
    batch=pointer.update(true,true,1,p,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::button_down);
    p.x=0.75f;batch=pointer.update(true,true,1,p,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::move);
    batch=pointer.update(true,true,1,outside,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::move&&pointer.held()==1);
    batch=pointer.update(true,true,0,outside,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::button_up&&pointer.held()==0);
    batch=pointer.update(true,true,0,p,32,utc);check(batch.count==2&&batch.events[1].wheel==16);
    batch=pointer.update(true,true,3,p,0,utc);check(batch.count==2&&pointer.held()==3);
    for(std::size_t i=0;i<batch.count;++i)check(ui::valid_event(batch.events[i],utc));
    ui::PointerBatch releases;pointer.close(utc,releases);check(releases.count==2&&pointer.held()==0&&!pointer.active());
    check(pointer.update(true,true,3,p,0,utc).count==0);check(pointer.update(true,true,0,p,0,utc).count==0);
    check(pointer.update(true,true,0,p,0,utc).count==1);
    check(pointer.update(true,true,1,p,0,utc).count==1);
    batch=pointer.update(false,true,1,p,0,utc);check(batch.count==1&&batch.events[0].kind==ui::Kind::button_up);
    check(pointer.update(true,false,0,p,0,utc).count==0&&!pointer.active());
    pointer.update(true,true,0,p,0,utc);pointer.update(true,true,0,p,0,utc);
    check(pointer.update(true,true,1,outside,0,utc).count==0&&!pointer.active());
    check(pointer.update(true,true,1,p,0,utc).count==0); // outside press must not turn into click on reentry.
    minecome::mouse::Notices notices;minecome::mouse::Notice notice;
    check(!notices.pop(notice));
    for(unsigned i=0;i<32;++i){minecome::mouse::Snapshot snapshot;snapshot.generation=i;check(notices.push({"test",minecome::mouse::Result::ok,snapshot}));}
    check(!notices.push({}));check(notices.take_dropped()==1&&notices.take_dropped()==0);
    for(unsigned i=0;i<32;++i)check(notices.pop(notice)&&notice.snapshot.generation==i);
    check(!notices.pop(notice));check(notices.push({"again",minecome::mouse::Result::ok,{}}));check(notices.pop(notice));
    std::cout<<"MOUSE_FORWARDING_TEST_PASS checks="<<checks<<" no_game=true\n";
}
