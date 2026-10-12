// SPDX-License-Identifier: GPL-3.0-or-later
#include "input_bindings.hpp"

#include <stdexcept>

// Primary Windows contracts inspected 2026-10-12:
// https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawkeyboard
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-mapvirtualkeyw
// https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input
// The last table specifies LeftControl scan001D / RightControl scanE01D.
// Numeric constants below mirror public Winuser.h so pure tests need no window/OS.
namespace minecome::input_capture {
namespace {
struct NamedKey { std::string_view name; std::uint16_t vkey; };
constexpr std::array<NamedKey, 9> named_keys{{
    {"UP", 0x26}, {"DOWN", 0x28}, {"LEFT", 0x25}, {"RIGHT", 0x27},
    {"SPACE", 0x20}, {"LSHIFT", 0xa0}, {"RSHIFT", 0xa1}, {"LCTRL", 0xa2}, {"RCTRL", 0xa3}
}};
std::uint16_t key_code(std::string_view name) {
    if (name.size() == 1 && name[0] >= 'A' && name[0] <= 'Z')
        return static_cast<std::uint16_t>(name[0]);
    for (const auto& key : named_keys) if (name == key.name) return key.vkey;
    throw std::invalid_argument("Unknown or noncanonical configured control key");
}
std::string key_name(std::uint16_t vkey) {
    if (vkey >= 'A' && vkey <= 'Z') return std::string(1, static_cast<char>(vkey));
    for (const auto& key : named_keys) if (vkey == key.vkey) return std::string(key.name);
    throw std::invalid_argument("Invalid configured virtual key");
}
}

InputBindings parse_bindings(std::string_view text) {
    if (text.empty() || text.size() > max_binding_text)
        throw std::invalid_argument("Bindings require six bounded canonical keys");
    std::array<std::uint16_t, control_count> keys{};
    std::size_t start{};
    for (unsigned index = 0; index < control_count; ++index) {
        const auto comma = text.find(',', start);
        const bool final = index + 1 == control_count;
        if (final ? comma != std::string_view::npos : comma == std::string_view::npos)
            throw std::invalid_argument("Bindings require exactly six keys");
        const auto end = comma == std::string_view::npos ? text.size() : comma;
        if (end == start) throw std::invalid_argument("Configured control key is empty");
        keys[index] = key_code(text.substr(start, end - start));
        for (unsigned previous = 0; previous < index; ++previous)
            if (keys[previous] == keys[index]) throw std::invalid_argument("Configured control keys must be unique");
        start = end + 1;
    }
    return InputBindings(keys);
}

InputBindings default_bindings() { return parse_bindings(default_binding_text); }

std::optional<Control> InputBindings::control_for(std::uint16_t vkey) const {
    for (unsigned index = 0; index < control_count; ++index)
        if (vkeys_[index] == vkey) return static_cast<Control>(index);
    return std::nullopt;
}

std::string InputBindings::canonical() const {
    std::string result;
    for (const auto vkey : vkeys_) {
        if (!result.empty()) result += ',';
        result += key_name(vkey);
    }
    return result;
}

std::uint16_t normalize_modifier_vkey(std::uint16_t raw_vkey, std::uint16_t raw_flags,
                                    std::uint16_t mapped_shift_vkey) {
    constexpr std::uint16_t key_break = 1, key_e0 = 2, key_e1 = 4;
    if (raw_flags & ~(key_break | key_e0 | key_e1)) return 0;
    if (raw_vkey == 0x10) { // VK_SHIFT: retain the platform's inspected scan-code translation.
        return mapped_shift_vkey == 0xa0 || mapped_shift_vkey == 0xa1 ? mapped_shift_vkey : 0;
    }
    if (raw_vkey == 0x11) { // VK_CONTROL: both sides have make001D, right has E0 prefix.
        if (raw_flags & key_e1) return 0;
        return raw_flags & key_e0 ? 0xa3 : 0xa2;
    }
    return raw_vkey;
}

} // namespace minecome::input_capture
