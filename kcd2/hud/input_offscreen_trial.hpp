#pragma once
#include "input_json.hpp"
#include "stream_contract.hpp"

namespace minecome::hud::input {
struct OffscreenTrial { std::uint64_t duration=0,unfocused_ticks=0; };
inline void validate_offscreen_identity(const json::Value &value,const stream::Identity &id) {
    if(value.at("schema").integer()!=1||value.at("run").text()!=id.run||
       value.at("target_pid").integer()!=id.target_pid||value.at("producer_pid").integer()!=id.producer_pid||
       value.at("target_start_filetime").integer()!=id.target_start||value.at("producer_start_filetime").integer()!=id.producer_start||
       value.at("expires_utc_ms").integer()!=id.expires_utc_ms||!value.at("ui_input_offscreen_trial").boolean()||
       !value.at("ui_input_offscreen_presentation").boolean())throw std::runtime_error("offscreen_trial_identity");
}
inline OffscreenTrial validate_offscreen_trial(const json::Value &value,const stream::Identity &id) {
    validate_offscreen_identity(value,id);
    const auto &trial=value.at("offscreen_trial");
    OffscreenTrial result{trial.at("duration_ms").integer(),trial.at("unfocused_ticks").integer()};
    if(!trial.at("completed").boolean()||!trial.at("presentation_suppressed").boolean()||
       trial.at("focused_ticks").integer()!=0||!result.unfocused_ticks||result.duration<12000||result.duration>stream::max_lease_ms||
       trial.at("timing").type!=json::Value::Type::object)throw std::runtime_error("offscreen_trial_incomplete");
    return result;
}
inline void validate_offscreen_final(const json::Value &value,const stream::Identity &id,std::uint64_t sent) {
    validate_offscreen_identity(value,id);
    const auto &events=value.at("lab_evidence").at("offscreen_trial_events");
    if(events.at("focus_interruptions").integer()!=0||events.at("focused_events_applied").integer()!=0)
        throw std::runtime_error("offscreen_focus_interrupted");
    if(value.at("result").text()!="input_passed"||sent!=31||events.at("unfocused_events_applied").integer()!=sent)
        throw std::runtime_error("offscreen_events_not_verified");
}
} // namespace minecome::hud::input
