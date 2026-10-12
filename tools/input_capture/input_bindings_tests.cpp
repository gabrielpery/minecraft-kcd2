// SPDX-License-Identifier: GPL-3.0-or-later
#include "input_bindings.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace ic = minecome::input_capture;
namespace {
unsigned checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class Function> void rejects(Function function) {
    bool rejected{};
    try { function(); } catch (const std::invalid_argument&) { rejected = true; }
    check(rejected, "Invalid binding configuration was accepted");
}
void defaults_and_allowlist() {
    const auto defaults = ic::default_bindings();
    check(defaults.canonical() == "W,S,A,D,SPACE,LSHIFT", "Default bindings changed");
    check(defaults.vkeys() == std::array<std::uint16_t, 6>{0x57, 0x53, 0x41, 0x44, 0x20, 0xa0},
          "Default virtual-key codes disagree with Winuser.h");
    check(!defaults.control_for(0x77), "F8 cannot be a recorded control");
    std::vector<std::pair<std::string, std::uint16_t>> keys;
    for (char letter = 'A'; letter <= 'Z'; ++letter) keys.emplace_back(std::string(1, letter), letter);
    for (auto key : std::vector<std::pair<std::string, std::uint16_t>>{
            {"UP",0x26}, {"DOWN",0x28}, {"LEFT",0x25}, {"RIGHT",0x27}, {"SPACE",0x20},
            {"LSHIFT",0xa0}, {"RSHIFT",0xa1}, {"LCTRL",0xa2}, {"RCTRL",0xa3}}) keys.push_back(key);
    for (const auto& [name, vkey] : keys) {
        std::string text = name;
        unsigned remaining = 5;
        for (char letter = 'A'; remaining && letter <= 'Z'; ++letter) {
            if (name == std::string(1, letter)) continue;
            text += ','; text += letter; --remaining;
        }
        const auto bindings = ic::parse_bindings(text);
        check(bindings.canonical() == text, "Canonical binding round trip failed");
        check(bindings.vkeys()[0] == vkey && bindings.control_for(vkey) == ic::Control::forward,
              "Allowed key maps to wrong semantic control");
    }
    const auto modifiers = ic::parse_bindings("LSHIFT,RSHIFT,LCTRL,RCTRL,UP,DOWN");
    check(modifiers.vkeys()[0] != modifiers.vkeys()[1] && modifiers.vkeys()[2] != modifiers.vkeys()[3],
          "Left/right modifiers must remain distinct");
    check(!modifiers.control_for('W'), "Default keys must not leak into a configured mapping");
}
void malformed_configurations() {
    for (const auto& text : std::vector<std::string>{
            "", "W,S,A,D,SPACE", "W,S,A,D,SPACE,LSHIFT,E", ",S,A,D,SPACE,LSHIFT",
            "W,,A,D,SPACE,LSHIFT", "W,S,A,D,SPACE,", "W,S,A,D,SPACE,LSHIFT,",
            "W,S,A,D,SPACE,W", "W,S,A,D,SPACE,F8", "w,S,A,D,SPACE,LSHIFT",
            "W,S,A,D,SPACE,LShift", "W,S,A,D,SPACE, LSHIFT", " W,S,A,D,SPACE,LSHIFT",
            "W,S,A,D,SPACE,LSHIFT\n", "W;S;A;D;SPACE;LSHIFT", "W,S,A,D,SPACE,SHIFT",
            "W,S,A,D,SPACE,CTRL", "W,S,A,D,SPACE,ALT", "W,S,A,D,SPACE,ESC",
            "W,S,A,D,SPACE,F1", "W,S,A,D,SPACE,0", "W,S,A,D,SPACE,VK_LSHIFT",
            "W,S,A,D,SPACE,`", std::string(42, 'A'), std::string(4096, 'W'),
            std::string("W,S,A,D,SPACE,LSHIFT\0", 21)}) {
        rejects([&] { (void)ic::parse_bindings(text); });
    }
    rejects([] { (void)ic::parse_bindings("W,S,A,D,SPACE,\xc3\x89"); });
}
void modifier_normalization() {
    for (std::uint16_t flags : {std::uint16_t{0}, std::uint16_t{1}}) {
        check(ic::normalize_modifier_vkey(0x10, flags, 0xa0) == 0xa0, "Mapped left SHIFT lost make/break");
        check(ic::normalize_modifier_vkey(0x10, flags, 0xa1) == 0xa1, "Mapped right SHIFT lost make/break");
        check(ic::normalize_modifier_vkey(0x11, flags) == 0xa2, "Nonextended CTRL must be left CTRL");
        check(ic::normalize_modifier_vkey(0x11, flags | 2) == 0xa3, "E0 CTRL must be right CTRL");
    }
    check(ic::normalize_modifier_vkey(0x10, 0, 0) == 0, "Unmapped SHIFT must fail closed");
    check(ic::normalize_modifier_vkey(0x10, 0, 0x11) == 0, "Non-SHIFT mapping must fail closed");
    check(ic::normalize_modifier_vkey(0x11, 4) == 0 && ic::normalize_modifier_vkey(0x11, 6) == 0,
          "E1 CTRL must not be interpreted as an ordinary side");
    check(ic::normalize_modifier_vkey('W', 8) == 0, "Unknown raw flags must fail closed");
    for (std::uint16_t vkey : {std::uint16_t{0xa0},std::uint16_t{0xa1},std::uint16_t{0xa2},std::uint16_t{0xa3},std::uint16_t{'W'},std::uint16_t{0x26}})
        check(ic::normalize_modifier_vkey(vkey, 1) == vkey, "Explicit/ordinary virtual key changed");
}
void configured_state_handoff() {
    const auto bindings = ic::parse_bindings("UP,DOWN,LEFT,RIGHT,SPACE,RCTRL");
    ic::InputState state;
    ic::ControlBits already_down{};
    already_down[static_cast<unsigned>(*bindings.control_for(ic::normalize_modifier_vkey(0x11, 2)))] = true;
    state.focus(true, already_down);
    state.f8(true);
    check(!state.sample().armed, "Configured held right CTRL must prevent arming");
    state.control(*bindings.control_for(ic::normalize_modifier_vkey(0x11, 3)), false);
    state.f8(false); state.f8(true);
    auto sample = state.sample();
    check(sample.armed && !sample.held[0] && !sample.held[5], "Configured mapping must preserve neutral arming");
    state.control(*bindings.control_for(0x26), true);
    state.control(*bindings.control_for(ic::normalize_modifier_vkey(0x11, 2)), true);
    sample = state.sample();
    check(sample.held[0] && sample.held[5], "Arrow/right CTRL mapping must drive semantic forward/sprint");
    state.control(*bindings.control_for(0x26), false);
    state.control(*bindings.control_for(ic::normalize_modifier_vkey(0x11, 3)), false);
    sample = state.sample();
    check(!sample.held[0] && !sample.held[5], "Configured make/break must release both controls");
    state.focus(false);
    check(!state.sample().armed, "Configured controls must preserve focus neutralization");
}
}
int main() {
    try {
        defaults_and_allowlist(); malformed_configurations(); modifier_normalization(); configured_state_handoff();
        std::cout << "INPUT_BINDINGS_TEST_PASS checks=" << checks << " physical_input_verified=false\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "INPUT_BINDINGS_TEST_FAIL " << error.what() << '\n';
        return 1;
    }
}
