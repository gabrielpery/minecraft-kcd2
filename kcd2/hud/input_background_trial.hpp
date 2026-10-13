#pragma once
#include "input_json.hpp"
#include "stream_contract.hpp"
#include <array>

namespace minecome::hud::input {
struct BackgroundPhase {
    std::uint64_t duration=0,unfocused_ticks=0,max_fps=0;
    bool vsync=false;
};
struct BackgroundTrial { std::array<BackgroundPhase,2> phases; };
inline BackgroundTrial validate_background_trial(const json::Value &value,const stream::Identity &id) {
    if(value.at("schema").integer()!=1||value.at("run").text()!=id.run||
       value.at("target_pid").integer()!=id.target_pid||value.at("producer_pid").integer()!=id.producer_pid||
       value.at("target_start_filetime").integer()!=id.target_start||value.at("producer_start_filetime").integer()!=id.producer_start||
       value.at("expires_utc_ms").integer()!=id.expires_utc_ms||!value.at("ui_input_background_trial").boolean())
        throw std::runtime_error("background_trial_identity");
    const auto &trial=value.at("background_trial");const auto &phases=trial.at("phases");
    if(!trial.at("completed").boolean()||phases.type!=json::Value::Type::array||phases.array.size()!=2)
        throw std::runtime_error("background_trial_incomplete");
    BackgroundTrial result;
    for(unsigned i=0;i<2;++i) {
        const auto &phase=phases.array[i];auto &out=result.phases[i];
        out.duration=phase.at("duration_ms").integer();out.unfocused_ticks=phase.at("unfocused_ticks").integer();
        out.max_fps=phase.at("max_fps").integer();out.vsync=phase.at("vsync").boolean();
        if(phase.at("name").text()!=(i?"trial":"baseline")||phase.at("focused_ticks").integer()!=0||
           out.duration<12000||out.duration>stream::max_lease_ms||!out.unfocused_ticks||!out.max_fps||out.max_fps>1000||
           (i&&(out.vsync||out.max_fps!=60)))throw std::runtime_error("background_trial_phase");
    }
    if(result.phases[0].duration+result.phases[1].duration>stream::max_lease_ms)
        throw std::runtime_error("background_trial_duration");
    return result;
}
} // namespace minecome::hud::input
