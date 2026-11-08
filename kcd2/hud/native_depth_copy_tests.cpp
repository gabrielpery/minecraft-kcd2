#include "native_depth_copy.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace copy = minecome::host_depth::copy;
namespace {
unsigned checks = 0;
void check(bool value, const char *message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}
void rejected_inputs() {
    check(copy::identify({}) == copy::ShaderRole::none, "empty shader rejected");
    std::vector<std::byte> bytes(copy::pixel_bytes + 1);
    for (const auto size : {std::size_t{1}, copy::vertex_bytes - 1, copy::vertex_bytes,
         copy::vertex_bytes + 1, copy::pixel_bytes - 1, copy::pixel_bytes, copy::pixel_bytes + 1})
        check(copy::identify(std::span(bytes).first(size)) == copy::ShaderRole::none,
            "wrong bytes rejected even at an exact recognized size");
    using R = copy::ShaderRole;
    for (const auto vertex : {R::none, R::fullscreen_vertex, R::depth_pixel})
        for (const auto pixel : {R::none, R::fullscreen_vertex, R::depth_pixel})
            check(copy::exact_shader_pair(vertex, pixel) ==
                (vertex == R::fullscreen_vertex && pixel == R::depth_pixel),
                "only ordered complete pair accepted");
    check(copy::exact_fullscreen_draw(3, 1, 0, 0), "exact direct triangle accepted");
    for (const auto value : {0u, 1u, 2u, 4u, 6u, UINT32_MAX})
        check(!copy::exact_fullscreen_draw(value, 1, 0, 0), "other vertex counts rejected");
    for (const auto value : {0u, 2u, UINT32_MAX})
        check(!copy::exact_fullscreen_draw(3, value, 0, 0), "other instance counts rejected");
    for (const auto value : {1u, 3u, UINT32_MAX}) {
        check(!copy::exact_fullscreen_draw(3, 1, value, 0), "base vertex rejected");
        check(!copy::exact_fullscreen_draw(3, 1, 0, value), "base instance rejected");
    }
}
std::vector<std::byte> read(const char *path) {
    const auto size = std::filesystem::file_size(path);
    if (size > 16384) throw std::runtime_error("fixture shader exceeds bound");
    std::vector<std::byte> bytes(static_cast<std::size_t>(size));
    std::ifstream input(path, std::ios::binary);
    if (!input.read(reinterpret_cast<char *>(bytes.data()), static_cast<std::streamsize>(bytes.size())))
        throw std::runtime_error("cannot read fixture shader");
    return bytes;
}
void local_shader(const char *path, copy::ShaderRole role) {
    auto bytes = read(path);
    check(copy::identify(bytes) == role, "inspected local shader identity matches");
    // Head, DXIL body, and tail mutations keep exact length but must fail.
    for (const auto index : {std::size_t{0}, bytes.size() / 2, bytes.size() - 1}) {
        bytes[index] ^= std::byte{1};
        check(copy::identify(bytes) == copy::ShaderRole::none, "one-bit mutation rejected");
        bytes[index] ^= std::byte{1};
    }
    check(copy::identify(std::span(bytes).first(bytes.size() - 1)) == copy::ShaderRole::none,
        "truncation rejected");
    bytes.push_back(std::byte{0});
    check(copy::identify(bytes) == copy::ShaderRole::none, "appended data rejected");
}
}
int main(int argc, char **argv) {
    try {
        if (argc != 1 && argc != 3) throw std::runtime_error("usage: native_depth_copy_tests [local-vs local-ps]");
        rejected_inputs();
        if (argc == 3) {
            local_shader(argv[1], copy::ShaderRole::fullscreen_vertex);
            local_shader(argv[2], copy::ShaderRole::depth_pixel);
        }
        std::cout << "NATIVE_DEPTH_COPY_TESTS checks=" << checks
            << " local_shader_pair=" << (argc == 3 ? "verified" : "not_requested") << " PASS\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
