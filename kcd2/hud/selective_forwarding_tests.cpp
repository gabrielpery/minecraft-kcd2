#include "selective_forwarding.hpp"
#include <cstdlib>
#include <iostream>
using namespace minecome::selective;
namespace {
unsigned checks=0;
void check(bool ok,const char *why){++checks;if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
Snapshot sample(Mode mode,std::uint64_t generation=10,unsigned flags=eligible|active){
    Snapshot s;s.flags=flags;s.mode=mode;s.generation=generation;s.token=123;s.lease_remaining_ms=100;return s;
}
using Step=ForwardingLease::Step;
ForwardingLease full(){ForwardingLease l;check(l.accept(Result::ok,sample(Mode::full),Mode::full,123,100)==Step::ready,"full acquisition");return l;}
}
int main(){
    ModeGate gate;
    check(gate.update(false,false,0,0,false,0,false)==Mode::full,"settle fully captured");
    check(gate.update(true,false,0,0,false,0,false)==Mode::full,"first neutral world frame");
    check(gate.update(true,false,0,0,false,0,false)==Mode::buttons,"second neutral world frame");
    check(gate.update(true,false,0,0,false,1,true)==Mode::buttons,"world click preserves camera");
    check(gate.update(true,false,0,0,true,1,true)==Mode::full,"E edge blocks camera immediately");
    check(gate.update(true,true,0,0,false,0,false)==Mode::full,"opening barrier");
    check(gate.update(true,false,1,1,false,0,false)==Mode::full,"inventory");
    check(gate.update(true,false,0,1,false,0,false)==Mode::full,"closed ACK but stale image");
    check(gate.update(true,false,0,0,false,1,false)==Mode::full,"held inventory click remains captured");
    check(gate.update(true,false,0,0,false,0,false)==Mode::full,"close neutral one");
    check(gate.update(true,false,0,0,false,0,false)==Mode::buttons,"close neutral two");
    for(unsigned invalid=2;invalid<16;++invalid){
        check(gate.update(true,false,invalid,0,false,0,true)==Mode::full,"unknown guest screen");
        check(gate.update(true,false,0,invalid,false,0,true)==Mode::full,"unknown uploaded screen");
    }
    auto l=full();
    check(l.allows(Mode::full)&&!l.allows(Mode::buttons),"initial full ownership");
    check(l.observe(Result::ok,sample(Mode::full),123,105),"query observes full");
    auto pending=sample(Mode::full,11,active|draining);
    check(l.accept(Result::draining,pending,Mode::buttons,123,110)==Step::pending,"switch drain starts");
    check(l.owned()&&l.pending()&&!l.allows(Mode::buttons)&&!l.allows(Mode::full),"no forwarding during drain");
    check(l.generation()==11&&l.request_mode(Mode::full)==Mode::buttons,"pending immutable request");
    check(l.observe(Result::ok,pending,123,120),"active own drain observed");
    check(l.accept(Result::draining,pending,Mode::buttons,123,150)==Step::pending,"same transition renew");
    auto done=sample(Mode::buttons,11);
    check(l.observe(Result::ok,done,123,151),"device completed before next render request");
    check(l.accept(Result::ok,done,Mode::buttons,123,151)==Step::ready,"buttons ready");
    check(l.allows(Mode::buttons)&&!l.pending(),"camera allowed after drain");
    check(l.accept(Result::ok,done,Mode::buttons,123,200)==Step::ready,"steady renewal preserves generation");
    auto back=sample(Mode::full,12,active|draining);
    check(l.accept(Result::draining,back,Mode::full,123,210)==Step::pending,"inventory drain");
    check(l.accept(Result::ok,sample(Mode::full,12),Mode::full,123,230)==Step::ready,"inventory ready");
    l.released();check(!l.owned()&&!l.pending()&&!l.allows(Mode::full),"release clears forwarding");
    for(unsigned i=0;i<8;++i){
        auto f=full();auto bad=sample(Mode::full);
        switch(i){
        case 0:bad.flags&=~active;break;case 1:bad.flags|=draining;break;case 2:bad.token++;break;
        case 3:bad.generation++;break;case 4:bad.lease_remaining_ms=0;break;
        case 5:bad.mode=Mode::buttons;break;case 6:bad.mode=Mode::none;break;case 7:bad.flags&=~eligible;break;
        }
        check(!f.observe(Result::ok,bad,123,110),"changed/expired/foreign query rejected");
        check(f.accept(Result::ok,bad,Mode::full,123,110)==Step::failed,"invalid renewal rejected");
    }
    for(auto result:{Result::bad_argument,Result::busy,Result::unavailable,Result::foreign_owner}){
        auto f=full();check(!f.observe(result,sample(Mode::full),123,110),"failed query closes");
        check(f.accept(result,sample(Mode::full),Mode::full,123,110)==Step::failed,"failed request closes");
    }
    auto expired=full();check(expired.accept(Result::draining,pending,Mode::buttons,123,110)==Step::pending,"deadline starts");
    check(expired.accept(Result::draining,pending,Mode::buttons,123,350)==Step::pending,"renew within original deadline");
    check(!expired.observe(Result::ok,pending,123,361),"pending timeout not refreshed by renewal");
    check(expired.accept(Result::ok,done,Mode::buttons,123,361)==Step::failed,"late device completion rejected");
    check(!expired.observe(Result::ok,pending,123,109),"clock regression rejected");
    auto changed=full();check(changed.accept(Result::draining,pending,Mode::buttons,123,110)==Step::pending,"pending retarget fixture");
    check(changed.accept(Result::draining,pending,Mode::full,123,111)==Step::failed,"cannot retarget pending drain");
    auto jump=full();check(jump.accept(Result::ok,sample(Mode::buttons,12),Mode::buttons,123,110)==Step::failed,"generation jumps rejected");
    auto same=full();check(same.accept(Result::ok,sample(Mode::buttons,10),Mode::buttons,123,110)==Step::failed,"switch requires new generation");
    auto lost=full();check(lost.accept(Result::draining,pending,Mode::buttons,123,110)==Step::pending,"lost ownership fixture");
    pending.flags=draining;pending.token=0;pending.lease_remaining_ms=0;
    check(!lost.observe(Result::ok,pending,123,111),"released/expired pending cleanup is not owned capture");
    check(lost.accept(Result::draining,pending,Mode::buttons,123,111)==Step::failed,"cannot reacquire unowned drain");
    std::cout<<"Selective forwarding checks: "<<checks<<'\n';
}
