#pragma once
// Original bounded coordination contract for the standalone bridge peer. These
// receipts prove protocol outcomes, never KCD composition or physical input.
#include "input_offscreen_trial.hpp"
#include <array>
#include <sstream>

namespace minecome::hud::input {
inline constexpr std::uint64_t stone_fixture_events=8;
struct StoneStep { std::uint32_t action,result,operation; };
inline constexpr std::array<StoneStep,6> stone_steps{{
    {1,1,1}, {2,1,2}, {1,2,0}, {1,2,0}, {1,1,1}, {2,1,2}
}};
inline std::uint64_t stone_number(const json::Value &value) {
    if(value.type!=json::Value::Type::number)throw std::runtime_error("stone_receipt_number_type");
    return value.integer();
}
inline std::string stone_step_request(const stream::Identity &id,std::size_t index) {
    if(!stream::valid_identity(id)||index>=stone_steps.size())throw std::runtime_error("stone_request_identity_or_step");
    const auto &step=stone_steps[index];std::ostringstream out;
    out << "{\"schema\":1,\"run\":\"" << id.run << "\",\"step\":" << index+1
        << ",\"action\":" << step.action << ",\"expected_result\":" << step.result << "}\n";
    return out.str();
}
inline void validate_stone_result(const json::Value &value,const stream::Identity &id,std::size_t index) {
    if(index>=stone_steps.size()||!stream::valid_identity(id))throw std::runtime_error("stone_result_identity_or_step");
    const auto &step=stone_steps[index];
    if(value.type!=json::Value::Type::object||value.object.size()!=8||
       stone_number(value.at("schema"))!=1||value.at("run").text()!=id.run||
       stone_number(value.at("step"))!=index+1||stone_number(value.at("request_id"))!=index+1||
       stone_number(value.at("action"))!=step.action||stone_number(value.at("result"))!=step.result||
       stone_number(value.at("block_event_operation"))!=step.operation||
       value.at("peer_kind").text()!="standalone_protocol_fixture")throw std::runtime_error("stone_result_mismatch");
}
inline void validate_stone_final(const json::Value &value,const stream::Identity &id,std::uint64_t sent,bool offscreen) {
    if(value.at("schema").integer()!=1||value.at("run").text()!=id.run||
       value.at("target_pid").integer()!=id.target_pid||value.at("producer_pid").integer()!=id.producer_pid||
       value.at("target_start_filetime").integer()!=id.target_start||value.at("producer_start_filetime").integer()!=id.producer_start||
       value.at("expires_utc_ms").integer()!=id.expires_utc_ms||
       value.at("ui_input_protocol").integer()!=1||
       !value.at("ui_input_fixture").boolean()||!value.at("ui_input_stone_fixture").boolean()||
       value.at("ui_input_offscreen_trial").boolean()!=offscreen||value.at("ui_input_offscreen_presentation").boolean()!=offscreen||
       value.at("result").text()!="input_passed"||sent!=stone_fixture_events)throw std::runtime_error("stone_final_mismatch");
    const auto pointer=value.object.find("ui_input_pointer_fixture");
    if(pointer!=value.object.end()&&pointer->second.boolean())throw std::runtime_error("stone_final_pointer_mode");
    if(offscreen) {
        validate_offscreen_identity(value,id,false);
        const auto &events=value.at("lab_evidence").at("offscreen_trial_events");
        if(events.at("focus_interruptions").integer()!=0||events.at("focused_events_applied").integer()!=0||
           events.at("unfocused_events_applied").integer()!=sent)throw std::runtime_error("stone_offscreen_events_not_verified");
    }
}
} // namespace minecome::hud::input
