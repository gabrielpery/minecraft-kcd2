#pragma once
#include "selective_capture_api.hpp"

namespace minecome::selective {
// Require a neutral boundary after inventory closes before returning camera
// motion to the host. Once established, world clicks keep the buttons lease.
class ModeGate {
public:
    Mode update(bool active,bool transition,unsigned screen,unsigned uploaded,bool toggle,
                unsigned buttons,bool already_buttons) noexcept {
        if(!active||transition||screen!=0||uploaded!=0||toggle){neutral_=0;return Mode::full;}
        if(already_buttons)return Mode::buttons;
        if(buttons){neutral_=0;return Mode::full;}
        if(neutral_<2)++neutral_;
        return neutral_>=2?Mode::buttons:Mode::full;
    }
private:
    unsigned neutral_=0;
};
// Addon-side ownership across full/button capture changes. The device thread
// completes each drain; render callbacks only renew the same bounded request.
class ForwardingLease {
public:
    enum class Step { failed, pending, ready };
    bool owned() const noexcept { return owned_; }
    bool pending() const noexcept { return pending_; }
    Mode request_mode(Mode desired) const noexcept { return pending_ ? requested_ : desired; }
    bool allows(Mode mode) const noexcept { return owned_ && !pending_ && mode_ == mode; }
    std::uint64_t generation() const noexcept { return generation_; }
    bool observe(Result result,const Snapshot &s,std::uint64_t token,std::uint64_t now) const noexcept {
        if(result!=Result::ok)return false;
        if(!owned_)return (s.flags&eligible)!=0;
        if(!(s.flags&active)||s.token!=token||s.generation!=generation_||!s.lease_remaining_ms)return false;
        if(pending_){
            if(now<pending_at_||now-pending_at_>250)return false;
            return (s.flags&draining)?s.mode==Mode::full:s.mode==requested_;
        }
        return !(s.flags&draining)&&(s.flags&eligible)&&s.mode==mode_;
    }
    Step accept(Result result,const Snapshot &s,Mode requested,std::uint64_t token,std::uint64_t now) noexcept {
        if((requested!=Mode::full&&requested!=Mode::buttons)||
           (result!=Result::ok&&result!=Result::draining)||!(s.flags&active)||s.token!=token||
           !s.generation||!s.lease_remaining_ms)return Step::failed;
        if(owned_){
            const bool switching=!pending_&&requested!=mode_;
            if(s.generation!=generation_+(switching?1:0))return Step::failed;
            if(pending_&&(requested!=requested_||now<pending_at_||now-pending_at_>250))return Step::failed;
        }
        if(result==Result::draining){
            if(!(s.flags&draining)||s.mode!=Mode::full)return Step::failed;
            if(!pending_)pending_at_=now;
            owned_=pending_=true;requested_=requested;generation_=s.generation;
            return Step::pending;
        }
        if((s.flags&draining)||s.mode!=requested||!(s.flags&eligible))return Step::failed;
        owned_=true;pending_=false;mode_=requested;generation_=s.generation;
        return Step::ready;
    }
    void released() noexcept { owned_=pending_=false; }
private:
    bool owned_=false,pending_=false;
    Mode mode_=Mode::none,requested_=Mode::none;
    std::uint64_t generation_=0,pending_at_=0;
};
}
