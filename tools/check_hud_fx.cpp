// Original offline checker. No device, swapchain, add-on, or game process is opened.
// Inspected ReShade v6.8.0, commit 18deaa52de0c425a78b329e9cb3c497281cd00ec:
// source/runtime.cpp selects DXBC shader model 5.1 for Direct3D 12;
// source/effect_codegen_dxbc.cpp embeds HLSL generation and D3DCompile.
#include "effect_codegen.hpp"
#include "effect_parser.hpp"
#include "effect_preprocessor.hpp"

#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>

namespace {
constexpr std::uintmax_t max_source_bytes = 1024 * 1024;
constexpr std::size_t max_preprocessed_bytes = 4 * 1024 * 1024;

std::size_t check(const std::filesystem::path &source, unsigned width, unsigned height) {
    reshadefx::preprocessor pp;
    pp.add_include_path(source.parent_path());
    pp.add_macro_definition("__RESHADE__", "60800");
    pp.add_macro_definition("__RESHADE_PERMUTATION__", "0");
    pp.add_macro_definition("__RESHADE_PERFORMANCE_MODE__", "0");
    pp.add_macro_definition("__RENDERER__", "49152"); // D3D12, 0xC000.
    pp.add_macro_definition("BUFFER_WIDTH", std::to_string(width));
    pp.add_macro_definition("BUFFER_HEIGHT", std::to_string(height));
    pp.add_macro_definition("BUFFER_RCP_WIDTH", "(1.0 / BUFFER_WIDTH)");
    pp.add_macro_definition("BUFFER_RCP_HEIGHT", "(1.0 / BUFFER_HEIGHT)");
    pp.add_macro_definition("BUFFER_COLOR_BIT_DEPTH", "8");
    pp.add_macro_definition("BUFFER_COLOR_SPACE", "1"); // SDR sRGB, not an HDR check.
    if (!pp.append_file(source)) throw std::runtime_error(pp.errors());
    if (pp.output().empty() || pp.output().size() > max_preprocessed_bytes)
        throw std::runtime_error("Empty or oversized preprocessed shader");

    std::unique_ptr<reshadefx::codegen> backend(reshadefx::create_codegen_dxbc(51, false, false, 1));
    reshadefx::parser parser;
    if (!parser.parse(pp.output(), backend.get()))
        throw std::runtime_error(pp.errors() + parser.errors());
    if (!pp.errors().empty() || !parser.errors().empty())
        std::cerr << pp.errors() << parser.errors();

    const auto &module = backend->module();
    if (module.techniques.empty() || module.entry_points.empty() || module.entry_points.size() > 32)
        throw std::runtime_error("Expected bounded effect techniques and shader entry points");
    bool vertex = false, pixel = false;
    for (const auto &[name, type] : module.entry_points) {
        if (type != reshadefx::shader_type::vertex && type != reshadefx::shader_type::pixel)
            throw std::runtime_error("HUD checker accepts vertex/pixel stages only");
        vertex |= type == reshadefx::shader_type::vertex;
        pixel |= type == reshadefx::shader_type::pixel;
        std::string binary, assembly, errors;
        if (!backend->assemble_code_for_entry_point(name, binary, assembly, errors) || binary.empty())
            throw std::runtime_error("DXBC compilation failed for " + name + ":\n" + errors);
        if (!errors.empty()) std::cerr << errors;
        std::cout << "MINECOME_HUD_FX_ENTRY_PASS entry=" << name
                  << " profile=" << (type == reshadefx::shader_type::vertex ? "vs_5_1" : "ps_5_1")
                  << " bytes=" << binary.size() << " width=" << width << " height=" << height << '\n';
    }
    if (!vertex || !pixel) throw std::runtime_error("HUD effect requires both vertex and pixel shader stages");
    return module.entry_points.size();
}
} // namespace

int wmain(int argc, wchar_t **argv) {
    try {
        if (argc != 2) throw std::runtime_error("Usage: minecome_check_hud_fx.exe <MineComeHud.fx>");
        const auto source = std::filesystem::absolute(std::filesystem::path(argv[1])).lexically_normal();
        if (!std::filesystem::is_regular_file(source) || std::filesystem::file_size(source) > max_source_bytes)
            throw std::runtime_error("Shader must be a regular file no larger than1MiB");
        const auto entries = check(source, 1920, 1080) + check(source, 1280, 720);
        std::cout << "MINECOME_HUD_FX_CHECK_PASS sdk=6.8.0 backend=dxbc shader_model=5.1"
                     " resolutions=2 compiled_entries=" << entries
                  << " game_render_verified=false\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "MINECOME_HUD_FX_CHECK_FAIL " << error.what() << '\n';
        return 1;
    }
}
