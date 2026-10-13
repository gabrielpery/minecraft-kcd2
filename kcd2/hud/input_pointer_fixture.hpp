#pragma once
#include "input_json.hpp"
#include "stream_contract.hpp"
#include <array>
#include <utility>

namespace minecome::hud::input {
constexpr std::uint64_t pointer_fixture_events=43;
struct PointerPhase { const char *name;std::uint64_t sequence; };
constexpr std::array<PointerPhase,11> pointer_phases{{
    {"opened",20},{"split",23},{"split_restored",25},{"picked_up",27},{"distributed",32},
    {"scrolled",33},{"scroll_restored",34},{"closed_held",38},{"reopened_held",40},{"late_release",41},{"complete",43}
}};
struct PointerTargets {
    std::array<std::pair<float,float>,3> slots; // Actual player inventory slots0,7,8.
    std::pair<float,float> drag_entry,scroll,blank;
};
inline void validate_pointer_identity(const json::Value &value,const stream::Identity &id) {
    if(value.at("schema").integer()!=1||value.at("run").text()!=id.run||
       value.at("target_pid").integer()!=id.target_pid||value.at("producer_pid").integer()!=id.producer_pid||
       value.at("target_start_filetime").integer()!=id.target_start||value.at("producer_start_filetime").integer()!=id.producer_start||
       value.at("expires_utc_ms").integer()!=id.expires_utc_ms||value.at("ui_input_protocol").integer()!=1||
       !value.at("ui_input_fixture").boolean()||!value.at("ui_input_pointer_fixture").boolean())
        throw std::runtime_error("pointer_fixture_identity");
}
inline std::pair<float,float> pointer_point(const json::Value &value) {
    const auto x=value.at("x").real(),y=value.at("y").real();
    if(x<0||x>1||y<0||y>1)throw std::runtime_error("pointer_target_coordinates");return {x,y};
}
inline PointerTargets pointer_targets(const json::Value &value) {
    PointerTargets out{};const auto &slots=value.at("slots");std::array<bool,3> seen{};
    if(slots.type!=json::Value::Type::array||slots.array.size()!=3)throw std::runtime_error("pointer_target_slots");
    for(const auto &slot:slots.array) {
        const auto index=slot.at("slot").integer();const unsigned target=index==0?0:index==7?1:index==8?2:3;
        if(target==3||seen[target])throw std::runtime_error("pointer_target_slot");seen[target]=true;out.slots[target]=pointer_point(slot);
    }
    out.drag_entry=pointer_point(value.at("drag_entry"));out.scroll=pointer_point(value.at("scroll"));out.blank=pointer_point(value.at("blank"));
    return out;
}
inline void validate_pointer_slots(const json::Value &value,std::size_t phase) {
    if(value.type!=json::Value::Type::array||value.array.size()!=9)throw std::runtime_error("pointer_slots_count");
    constexpr std::array<const char *,9> initial_items{"minecraft:stone","minecraft:dirt","minecraft:cobblestone","minecraft:oak_planks","minecraft:stick","minecraft:apple","minecraft:torch","minecraft:air","minecraft:air"};
    constexpr std::array<std::uint64_t,9> initial_counts{64,32,16,8,3,2,12,0,0};
    std::array<bool,9> seen{};
    for(const auto &slot:value.array) {
        const auto index=slot.at("slot").integer();if(index>8||seen[index])throw std::runtime_error("pointer_slot_index");seen[index]=true;
        const char *item=initial_items[index];auto count=initial_counts[index];
        if(index==0&&phase==1)count=32;
        if(index==0&&phase>=3){item="minecraft:air";count=0;}
        if(index>=7&&phase>=4){item="minecraft:stone";count=32;}
        if(slot.at("item").text()!=item||slot.at("count").integer()!=count)throw std::runtime_error("pointer_slot_contents");
    }
}
inline float validate_pointer_phase(const json::Value &phase,std::size_t index) {
    if(index>=pointer_phases.size()||phase.at("stage").text()!=pointer_phases[index].name||
       phase.at("applied_sequence").integer()!=pointer_phases[index].sequence||!phase.at("server_confirmed").boolean()||
       phase.at("server_observation_age_ms").integer()>250)throw std::runtime_error("pointer_phase_identity");
    validate_pointer_slots(phase.at("client_slots"),index);validate_pointer_slots(phase.at("server_slots"),index);
    const auto cursor_count=index==1?32u:index==3?64u:0u;const auto &cursor=phase.at("cursor");
    if(cursor.at("item").text()!=(cursor_count?"minecraft:stone":"minecraft:air")||cursor.at("count").integer()!=cursor_count)
        throw std::runtime_error("pointer_cursor_contents");
    const bool inventory=index!=7&&index!=10;
    if(phase.at("inventory_open").boolean()!=inventory||phase.at("held_buttons").integer()!=0||
       phase.at("pending_releases").integer()!=((index==7||index==8)?1u:0u)||phase.at("active_button").real()!=-1||
       phase.at("cleanup_releases").integer()!=(index>=7?1u:0u)||phase.at("late_releases_consumed").integer()!=(index>=9?1u:0u)||
       phase.at("screen_generation").integer()!=(index>=8?2u:1u)||
       phase.at("wheel_calls").integer()!=(index>=6?2u:index==5?1u:0u)||
       (index>=4&&phase.at("mouse_drag_calls").integer()<2))throw std::runtime_error("pointer_phase_callbacks");
    const auto initial=phase.at("initial_scroll_position").real();if(initial<0||initial>1)throw std::runtime_error("pointer_scroll_position");
    if(inventory) {
        const auto position=phase.at("scroll_position").real();if(position<0||position>1)throw std::runtime_error("pointer_scroll_position");
        if(index==5) {
            if(position<=initial||phase.at("grid_matches_initial").boolean())throw std::runtime_error("pointer_scroll_not_changed");
        } else if(std::abs(position-initial)>0.000001f||!phase.at("grid_matches_initial").boolean())throw std::runtime_error("pointer_scroll_not_restored");
    } else if(phase.at("scroll_position").type!=json::Value::Type::null_)throw std::runtime_error("pointer_closed_scroll");
    if(index>=5&&!phase.at("grid_changed_verified").boolean())throw std::runtime_error("pointer_grid_change_missing");
    return initial;
}
inline void validate_pointer_final(const json::Value &value,const stream::Identity &id,std::uint64_t sent,float initial_scroll) {
    validate_pointer_identity(value,id);const auto &lab=value.at("lab_evidence");const auto &proof=lab.at("pointer_evidence");
    if(value.at("result").text()!="input_passed"||sent!=pointer_fixture_events||lab.at("input_events_applied").integer()!=sent||
       !lab.at("pointer_fixture").boolean()||!proof.at("completed").boolean())throw std::runtime_error("pointer_final_incomplete");
    if(std::abs(validate_pointer_phase(proof,pointer_phases.size()-1)-initial_scroll)>0.000001f)throw std::runtime_error("pointer_initial_scroll_changed");
}
} // namespace minecome::hud::input
