#include "input_stone_fixture.hpp"
#include <iostream>
#include <functional>

namespace ui=minecome::hud::input;
namespace st=minecome::hud::stream;
namespace {
unsigned checks=0;
void check(bool value,const char *message) {++checks;if(!value)throw std::runtime_error(message);}
void rejects(const std::function<void()> &run,const char *message) {
    bool rejected=false;try {run();}catch(const std::exception &) {rejected=true;}check(rejected,message);
}
ui::json::Value json(const std::string &text) {return ui::json::Parser(text).parse();}
ui::json::Value receipt(const st::Identity &id,std::size_t index) {
    const auto &step=ui::stone_steps.at(index);std::ostringstream out;
    out << "{\"schema\":1,\"run\":\"" << id.run << "\",\"step\":" << index+1 << ",\"request_id\":" << index+1
        << ",\"action\":" << step.action << ",\"result\":" << step.result << ",\"block_event_operation\":" << step.operation
        << ",\"peer_kind\":\"standalone_protocol_fixture\"}";
    return json(out.str());
}
void run() {
    const st::Identity id{"0123456789abcdef0123456789abcdef",11,22,33,44,1000};
    check(ui::stone_fixture_events==8,"exact eight keyboard edges");
    check(ui::stone_steps.size()==6,"exact six protocol steps");
    for(std::size_t index=0;index<ui::stone_steps.size();++index) {
        const auto request=json(ui::stone_step_request(id,index));
        check(request.object.size()==5&&request.at("schema").integer()==1&&request.at("run").text()==id.run&&
              request.at("step").integer()==index+1&&request.at("action").integer()==ui::stone_steps[index].action&&
              request.at("expected_result").integer()==ui::stone_steps[index].result,"immutable request contract");
        const auto valid=receipt(id,index);ui::validate_stone_result(valid,id,index);check(true,"matching result accepted");
        for(const auto key:{"schema","step","request_id","action","result","block_event_operation"}) {
            auto changed=valid;changed.object.at(key)=json("999");
            rejects([&] {ui::validate_stone_result(changed,id,index);},"wrong result integer rejected");
            changed=valid;changed.object.at(key)=json("\""+changed.object.at(key).scalar+"\"");
            rejects([&] {ui::validate_stone_result(changed,id,index);},"coerced string integer rejected");
        }
        for(const auto key:{"schema","run","step","request_id","action","result","block_event_operation","peer_kind"}) {
            auto missing=valid;missing.object.erase(key);
            rejects([&] {ui::validate_stone_result(missing,id,index);},"missing result field rejected");
        }
        auto changed=valid;changed.object.at("run")=json("\"fedcba9876543210fedcba9876543210\"");
        rejects([&] {ui::validate_stone_result(changed,id,index);},"foreign run rejected");
        changed=valid;changed.object.at("peer_kind")=json("\"live_host\"");
        rejects([&] {ui::validate_stone_result(changed,id,index);},"peer provenance cannot claim live host");
        changed=valid;changed.object.emplace("extra",json("true"));
        rejects([&] {ui::validate_stone_result(changed,id,index);},"unknown result fields rejected");
        rejects([&] {ui::validate_stone_result(valid,id,(index+1)%6);},"replayed result rejected");
    }
    rejects([&] {ui::stone_step_request(id,6);},"out of range request rejected");
    rejects([&] {ui::validate_stone_result(receipt(id,0),id,6);},"out of range result rejected");
    auto invalid=id;invalid.run="bad";
    rejects([&] {ui::stone_step_request(invalid,0);},"malformed request identity rejected");
    rejects([&] {ui::validate_stone_result(receipt(id,0),invalid,0);},"malformed result identity rejected");
    auto final=json(R"({"schema":1,"run":"0123456789abcdef0123456789abcdef","target_pid":22,"producer_pid":11,"target_start_filetime":"44","producer_start_filetime":"33","expires_utc_ms":1000,"ui_input_protocol":1,"ui_input_fixture":true,"ui_input_stone_fixture":true,"ui_input_pointer_fixture":false,"ui_input_offscreen_trial":true,"ui_input_offscreen_presentation":true,"result":"input_passed","lab_evidence":{"offscreen_trial_events":{"focus_interruptions":0,"focused_events_applied":0,"unfocused_events_applied":8}}})");
    ui::validate_stone_final(final,id,8,true);check(true,"matching offscreen final accepted");
    rejects([&] {ui::validate_stone_final(final,id,7,true);},"missing keyboard edge rejected");
    rejects([&] {ui::validate_stone_final(final,id,8,false);},"offscreen mode mismatch rejected");
    for(const auto key:{"target_pid","producer_pid","target_start_filetime","producer_start_filetime","expires_utc_ms","schema","ui_input_protocol"}) {
        auto changed=final;changed.object.at(key)=json("999");
        rejects([&] {ui::validate_stone_final(changed,id,8,true);},"final identity mismatch rejected");
    }
    for(const auto key:{"ui_input_fixture","ui_input_stone_fixture","ui_input_offscreen_trial","ui_input_offscreen_presentation"}) {
        auto changed=final;changed.object.at(key)=json("false");
        rejects([&] {ui::validate_stone_final(changed,id,8,true);},"final required mode rejected");
    }
    for(const auto key:{"focus_interruptions","focused_events_applied","unfocused_events_applied"}) {
        auto changed=final;changed.object.at("lab_evidence").object.at("offscreen_trial_events").object.at(key)=json("1");
        rejects([&] {ui::validate_stone_final(changed,id,8,true);},"final unfocused evidence mismatch rejected");
    }
    auto changed=final;changed.object.at("ui_input_pointer_fixture")=json("true");
    rejects([&] {ui::validate_stone_final(changed,id,8,true);},"mixed pointer final rejected");
    changed=final;changed.object.at("result")=json("\"input_completed\"");
    rejects([&] {ui::validate_stone_final(changed,id,8,true);},"nonfixture completion rejected");
}
}
int main() {
    try {run();std::cout << "HUD_STONE_FIXTURE_TESTS passed checks=" << checks << '\n';return 0;}
    catch(const std::exception &e){std::cerr << "HUD_STONE_FIXTURE_TESTS failed " << e.what() << '\n';return 1;}
}
