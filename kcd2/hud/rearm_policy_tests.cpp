#include "rearm_policy.hpp"
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>
namespace r = minecome::hud::rearm;
namespace {
unsigned checks = 0;
void check(bool condition, const char *message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
r::Arm arm(unsigned index = 1) {
    return {{std::string(32, static_cast<char>('0' + index)), std::string(64, static_cast<char>('a' + index)),
             44, 100 + index, 1000, 2000 + index}, {1280, 720, 5120}, 10000};
}
r::Retirement proof(const r::Generation &owner, std::uint64_t at = 210) {
    return {{owner, at, {true, true, 12, 12}},
            {owner, at, {true, 0, 0, false}},
            {owner, at, {true, true, true, true}},
            {owner, at, {true, true, false}},
            {owner, at, {true}},
            {owner, at, {true, true, true, true, std::string(64, 'f')}}};
}
r::Policy retiring() {
    r::Policy p;
    check(p.admit(arm(), true, 1000, 100) == r::Result::accepted, "initial explicit admission");
    const auto owner = p.current();
    check(p.begin_retirement(owner, r::Outcome::completed, 200) == r::Result::accepted, "retirement starts");
    return p;
}
r::Policy idle() {
    auto p = retiring();
    check(p.retire(proof(p.current()), 220) == r::Result::accepted, "complete retirement");
    return p;
}
}
int main() {
    r::Policy p;
    check(p.phase() == r::Phase::empty && p.admitted_count() == 0, "initial state owns nothing");
    check(p.admit(arm(), false, 1000, 100) == r::Result::explicit_request_required, "no automatic initial arm");
    check(p.admit(arm(), true, 1000, 100) == r::Result::accepted, "first explicit arm");
    auto first = p.current();
    const auto &retained_snapshot = p.current();
    check(p.accepts_callbacks(first) && first.ordinal == 1 && p.deadline_steady_ms() == 9100, "immutable first generation");
    check(p.admit(arm(2), true, 1100, 200) == r::Result::wrong_phase && p.current() == first, "cannot replace active identity");
    auto future = first; future.ordinal = 2;
    check(p.begin_retirement(future, r::Outcome::failed, 200) == r::Result::wrong_generation && p.accepts_callbacks(first), "foreign callback cannot terminate owner");
    check(p.begin_retirement(first, r::Outcome::completed, 200) == r::Result::accepted, "explicit retirement");
    check(!p.accepts_callbacks(first) && p.phase() == r::Phase::retiring, "retirement rejects callbacks immediately");
    check(p.admit(arm(2), true, 1100, 205) == r::Result::wrong_phase, "new arm cannot skip cleanup");
    check(p.retire(proof(first), 220) == r::Result::accepted && p.phase() == r::Phase::idle, "cleanup makes idle, not armed");
    check(!p.accepts_callbacks(first) && p.current() == first, "retired generation remains attributable");
    check(p.admit(arm(2), false, 1200, 230) == r::Result::explicit_request_required, "clean completion never automatically rearms");
    check(p.admit(arm(2), true, 1200, 230) == r::Result::accepted, "distinct explicitly requested second generation");
    const auto second = p.current();
    check(second.ordinal == 2 && p.accepts_callbacks(second) && !p.accepts_callbacks(first), "only current generation accepts work");
    check(retained_snapshot == first && !p.accepts_callbacks(retained_snapshot), "retained snapshot cannot alias newly admitted owner");
    check(p.fail(first) == r::Result::wrong_generation && p.accepts_callbacks(second), "late first-generation failure cannot close second");
    check(p.begin_retirement(second, r::Outcome::completed, 300) == r::Result::accepted, "second retirement");
    check(p.retire(proof(first, 310), 320) == r::Result::receipt_identity, "old completion cannot retire new owner");
    check(p.retire(proof(second, 310), 320) == r::Result::accepted && p.phase() == r::Phase::exhausted, "two completed sessions exhaust policy");
    check(p.admit(arm(3), true, 1300, 330) == r::Result::session_limit && p.admitted_count() == 2, "third explicit session forbidden");

    // Each independent real-world prerequisite must be represented. No default
    // zero count or a successful controller summary can substitute for it.
    const std::vector<std::function<void(r::Retirement &)>> missing = {
        [](auto &v){v.input.value.host_closed=false;}, [](auto &v){v.input.value.guest_closed=false;},
        [](auto &v){--v.input.value.events_acknowledged;}, [](auto &v){++v.input.value.events_acknowledged;},
        [](auto &v){v.queues.value.snapshot_complete=false;}, [](auto &v){v.queues.value.input_pending=1;},
        [](auto &v){v.queues.value.world_pending=1;}, [](auto &v){v.queues.value.pending_world_click=true;},
        [](auto &v){v.renderer.value.publication_withdrawn=false;}, [](auto &v){v.renderer.value.callbacks_retired=false;},
        [](auto &v){v.renderer.value.resident_generation_retired=false;}, [](auto &v){v.renderer.value.hidden=false;},
        [](auto &v){v.capture.value.released=false;}, [](auto &v){v.capture.value.drained=false;},
        [](auto &v){v.capture.value.active=true;}, [](auto &v){v.producer.value.exited=false;},
        [](auto &v){v.controller.value.verified=false;}, [](auto &v){v.controller.value.aimed_cleanup=false;},
        [](auto &v){v.controller.value.movement_restored=false;}, [](auto &v){v.controller.value.guest_cleanup=false;},
        [](auto &v){v.controller.value.verification_sha256.clear();}, [](auto &v){v.controller.value.verification_sha256[0]='G';}
    };
    for (const auto &mutate : missing) {
        auto q = retiring(); auto v = proof(q.current()); mutate(v);
        check(q.retire(v, 220) == r::Result::incomplete_cleanup && q.phase() == r::Phase::retiring, "missing proof cannot permit next arm");
        check(q.admit(arm(2), true, 1200, 230) == r::Result::wrong_phase, "failed cleanup still bars rearm");
    }
    // Mix-and-match receipts are invalid even if every success flag is true.
    for (unsigned field=0; field<6; ++field) for (unsigned identity=0; identity<7; ++identity) {
        auto q = retiring(); auto v = proof(q.current());
        auto *owner = std::vector<r::Generation *>{&v.input.owner,&v.queues.owner,&v.renderer.owner,&v.capture.owner,&v.producer.owner,&v.controller.owner}[field];
        switch (identity) {
            case 0: ++owner->ordinal; break;
            case 1: owner->arm.identity.run[0]='9'; break;
            case 2: ++owner->arm.identity.target_pid; break;
            case 3: ++owner->arm.identity.target_start; break;
            case 4: ++owner->arm.identity.producer_pid; break;
            case 5: ++owner->arm.identity.producer_start; break;
            case 6: owner->arm.identity.arm_sha256[0]='0'; break;
        }
        check(q.retire(v, 220) == r::Result::receipt_identity, "every receipt is tied to the complete old owner");
    }
    for (unsigned field=0; field<6; ++field) for (const auto at : {0ull,199ull,221ull}) {
        auto q = retiring(); auto v = proof(q.current());
        *std::vector<std::uint64_t *>{&v.input.observed_steady_ms,&v.queues.observed_steady_ms,&v.renderer.observed_steady_ms,
            &v.capture.observed_steady_ms,&v.producer.observed_steady_ms,&v.controller.observed_steady_ms}[field] = at;
        check(q.retire(v, 220) == r::Result::receipt_time, "missing, pre-retirement or future receipt cannot retire");
    }
    const std::vector<std::function<void(r::Arm &)>> invalid = {
        [](auto &a){a.identity.run.clear();}, [](auto &a){a.identity.run[0]='G';},
        [](auto &a){a.identity.arm_sha256.pop_back();}, [](auto &a){a.identity.arm_sha256[0]='Z';},
        [](auto &a){a.identity.target_pid=0;}, [](auto &a){a.identity.producer_pid=0;},
        [](auto &a){a.identity.producer_pid=a.identity.target_pid;}, [](auto &a){a.identity.target_start=0;},
        [](auto &a){a.identity.producer_start=0;}, [](auto &a){a.expires_utc_ms=1000;},
        [](auto &a){a.expires_utc_ms=181001;}, [](auto &a){a.image.width=0;},
        [](auto &a){a.image.height=0;}, [](auto &a){a.image.width=1921;a.image.pitch=7684;},
        [](auto &a){a.image.height=1081;}, [](auto &a){--a.image.pitch;}
    };
    for (const auto &mutate : invalid) {
        r::Policy q; auto a = arm(); mutate(a);
        check(q.admit(a, true, 1000, 100) == r::Result::invalid_arm && q.admitted_count() == 0, "invalid arm never acquires generation");
    }
    const std::vector<std::pair<std::function<void(r::Arm &)>,r::Result>> changed = {
        {[](auto &a){++a.identity.target_pid;},r::Result::wrong_target},
        {[](auto &a){++a.identity.target_start;},r::Result::wrong_target},
        {[](auto &a){a.identity.run=arm().identity.run;},r::Result::replayed_arm},
        {[](auto &a){a.identity.arm_sha256=arm().identity.arm_sha256;},r::Result::replayed_arm},
        {[](auto &a){a.identity.producer_pid=arm().identity.producer_pid;},r::Result::reused_producer},
        {[](auto &a){a.identity.producer_start=arm().identity.producer_start;},r::Result::reused_producer},
        {[](auto &a){a.identity.producer_start=1;},r::Result::reused_producer},
        {[](auto &a){a.image.width=640;a.image.pitch=2560;},r::Result::image_changed},
        {[](auto &a){a.image.height=480;},r::Result::image_changed}
    };
    for (const auto &[mutate, expected] : changed) {
        auto q = idle(); const auto old=q.current(); auto a=arm(2); mutate(a);
        check(q.admit(a, true, 1200, 230) == expected && q.current() == old && q.phase() == r::Phase::idle, "second arm preserves target, format and distinct identity");
    }
    for (const bool before_retirement : {false,true}) {
        auto q = retiring();
        if (before_retirement) {q=r::Policy{};check(q.admit(arm(),true,1000,100)==r::Result::accepted,"failure setup");}
        check(q.fail(q.current()) == r::Result::session_failed && q.phase() == r::Phase::failed, "failure latches permanently");
        check(q.admit(arm(2),true,1200,230)==r::Result::session_failed, "even an explicit new arm cannot erase failure");
        check(q.retire(proof(q.current()),240)==r::Result::wrong_phase, "late success receipt cannot recover failed owner");
    }
    r::Policy failed;
    check(failed.admit(arm(),true,1000,100)==r::Result::accepted,"failed close setup");
    check(failed.begin_retirement(failed.current(),r::Outcome::failed,200)==r::Result::session_failed,"unsuccessful close cannot enter idle");
    check(failed.admit(arm(2),true,1200,230)==r::Result::session_failed,"failed close cannot rearm");
    auto clock = retiring();
    check(clock.retire(proof(clock.current()),199)==r::Result::clock_regressed && clock.phase()==r::Phase::failed,"retirement clock regression fails closed");
    auto old_clock = idle();
    check(old_clock.admit(arm(2),true,1200,219)==r::Result::clock_regressed,"new admission cannot precede completed retirement");
    r::Policy overflow;
    check(overflow.admit(arm(),true,1000,std::numeric_limits<std::uint64_t>::max()-1)==r::Result::invalid_arm,"deadline overflow rejected");
    r::Policy exact;
    auto maximum=arm();maximum.expires_utc_ms=181000;maximum.image={1920,1080,7680};
    check(exact.admit(maximum,true,1000,100)==r::Result::accepted && exact.deadline_steady_ms()==180100,"existing maximum transport lease and image bounds exact");
    std::cout << "HUD rearm policy: " << checks << " checks passed (standalone policy only; no addon integration).\n";
}
