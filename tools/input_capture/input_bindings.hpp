// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "input_state.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace minecome::input_capture {

inline constexpr std::string_view default_binding_text = "W,S,A,D,SPACE,LSHIFT";
inline constexpr std::size_t max_binding_text = 41; // Six longest tokens plus five commas.

// Explicit virtual-key configuration, never an effective-game-binding discovery.
// Positions are forward, back, left, right, jump, sprint. F8 remains reserved.
class InputBindings {
public:
    const std::array<std::uint16_t, control_count>& vkeys() const { return vkeys_; }
    std::optional<Control> control_for(std::uint16_t vkey) const;
    std::string canonical() const;
private:
    explicit InputBindings(std::array<std::uint16_t, control_count> vkeys) : vkeys_(vkeys) {}
    std::array<std::uint16_t, control_count> vkeys_;
    friend InputBindings parse_bindings(std::string_view text);
};

// Exact uppercase CSV: A-Z, UP/DOWN/LEFT/RIGHT, SPACE, LSHIFT/RSHIFT, LCTRL/RCTRL.
// Throws invalid_argument for unknown/duplicate/empty/noncanonical/overlong input.
InputBindings parse_bindings(std::string_view text);
InputBindings default_bindings();

// No OS calls. The platform supplies MapVirtualKeyW's left/right SHIFT result.
// Generic CTRL uses RAWKEYBOARD's E0 flag; E1/unknown modifier mappings fail closed.
// Zero means an invalid modifier mapping, never a configured control.
std::uint16_t normalize_modifier_vkey(std::uint16_t raw_vkey, std::uint16_t raw_flags,
                                    std::uint16_t mapped_shift_vkey = 0);

} // namespace minecome::input_capture
