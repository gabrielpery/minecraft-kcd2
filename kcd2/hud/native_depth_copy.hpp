#pragma once

// Exact KCD2Mod 1.5.5 shader identities; no proprietary bytecode is embedded.
// Inspected PostEffects.cfx:53-59 (TexToTexVS) and :734-750 (DepthToDepthPS).
// The captured DXIL pair reads source t0 with point sampler s1 and writes its
// unchanged x component to SV_Depth. Identity alone never proves a depth copy:
// the integration must also validate the direct draw, absent extra stages,
// source SRV/sampler, viewport, target, and same-presentation source proof.
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace minecome::host_depth::copy {
enum class ShaderRole { none, fullscreen_vertex, depth_pixel };
inline constexpr std::size_t vertex_bytes = 3124, pixel_bytes = 3828;
using Digest = std::array<unsigned char, 32>;
inline constexpr Digest vertex_sha256{
    0xca,0x98,0x0e,0x93,0x1e,0x8d,0x44,0x58,0x40,0xde,0x21,0x9a,0xa0,0x80,0x9c,0xfb,
    0xaa,0x81,0x43,0x1c,0xe5,0xa8,0xe5,0xe9,0x7e,0xb5,0xfc,0x80,0x5b,0xcb,0x73,0x55};
inline constexpr Digest pixel_sha256{
    0xa4,0xfc,0xf8,0xa3,0x1f,0x4a,0x7d,0xb4,0x71,0xa6,0x7f,0x03,0x07,0x0a,0x89,0x9e,
    0xd0,0x8d,0xb8,0x25,0x49,0xb0,0x0c,0x70,0x5c,0x96,0x9e,0x36,0x91,0xf0,0xee,0x62};

inline ShaderRole identify(std::span<const std::byte> code) noexcept {
    // Reject all other lengths before loading a provider or reading code.
    if ((code.size() != vertex_bytes && code.size() != pixel_bytes) || !code.data())
        return ShaderRole::none;
    struct Hash {
        BCRYPT_ALG_HANDLE algorithm = nullptr;
        BCRYPT_HASH_HANDLE hash = nullptr;
        ~Hash() {
            if (hash) BCryptDestroyHash(hash);
            if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
        }
    } state;
    Digest digest{};
    if (BCryptOpenAlgorithmProvider(&state.algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
        BCryptCreateHash(state.algorithm, &state.hash, nullptr, 0, nullptr, 0, 0) < 0 ||
        BCryptHashData(state.hash, reinterpret_cast<PUCHAR>(const_cast<std::byte *>(code.data())),
            static_cast<ULONG>(code.size()), 0) < 0 ||
        BCryptFinishHash(state.hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0)
        return ShaderRole::none;
    if (code.size() == vertex_bytes && digest == vertex_sha256) return ShaderRole::fullscreen_vertex;
    if (code.size() == pixel_bytes && digest == pixel_sha256) return ShaderRole::depth_pixel;
    return ShaderRole::none;
}

inline constexpr bool exact_shader_pair(ShaderRole vertex, ShaderRole pixel) noexcept {
    return vertex == ShaderRole::fullscreen_vertex && pixel == ShaderRole::depth_pixel;
}

// Call only for a direct non-indexed draw; indexed and indirect paths must
// reject before this predicate. TexToTexVS consumes exactly vertex IDs 0,1,2.
inline constexpr bool exact_fullscreen_draw(std::uint32_t vertices, std::uint32_t instances,
    std::uint32_t first_vertex, std::uint32_t first_instance) noexcept {
    return vertices == 3 && instances == 1 && first_vertex == 0 && first_instance == 0;
}
}
