#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace minecome::protocol {
using Bytes = std::vector<std::uint8_t>;
constexpr std::size_t header_size = 32;
constexpr std::uint32_t max_payload = 65536;
constexpr std::uint32_t CAP_STONE_INPUT = 1;
constexpr std::uint64_t maximum_input_id = 9007199254740991ULL;
enum class Type : std::uint16_t { hello=1, heartbeat=2, kcd_pose=3, mc_pose=4, block_event=5, error=6, goodbye=7, stone_input_request=8, stone_input_result=9 };
enum class Role : std::uint32_t { kcd=1, minecraft=2, harness=3 };
enum class Space : std::uint32_t { kcd=1, minecraft=2 };
struct Header {
    Type type{};
    std::uint32_t payload_size{};
    std::uint64_t sequence{};
    std::uint64_t timestamp_us{};
    std::uint16_t minor{}; // Appended to preserve existing aggregate initializers.
};
struct Hello { Role role{}; std::uint32_t capabilities{}; std::string name; std::string credential; };
struct Vec3 { double x{}, y{}, z{}; };
struct Quaternion { double x{}, y{}, z{}, w{1}; };
struct Pose {
    Vec3 player, camera;
    Quaternion orientation;
    double vertical_fov{1.0471975511965976};
    Vec3 kcd_origin;
    double blocks_per_unit{1};
    Space space{Space::kcd};
    std::uint32_t flags{};
};
struct BlockEvent { std::uint32_t operation{}; std::int32_t x{}, y{}, z{}; std::string block_id; };
struct StoneInputRequest { std::uint64_t id{}; std::uint32_t action{}; };
enum class StoneInputResultCode : std::uint32_t { accepted=1, unavailable=2, stale=3, busy=4, occupied=5, absent=6, vanilla_failed=7 };
struct StoneInputResult { std::uint64_t id{}; std::uint32_t action{}; StoneInputResultCode result{}; };
Bytes encode_header(const Header&);
Header decode_header(std::span<const std::uint8_t>);
Bytes encode(const Hello&);
Hello decode_hello(std::span<const std::uint8_t>);
Bytes encode(const Pose&);
Pose decode_pose(std::span<const std::uint8_t>);
Bytes encode(const BlockEvent&);
BlockEvent decode_block_event(std::span<const std::uint8_t>);
Bytes encode(const StoneInputRequest&);
StoneInputRequest decode_stone_input_request(std::span<const std::uint8_t>);
Bytes encode(const StoneInputResult&);
StoneInputResult decode_stone_input_result(std::span<const std::uint8_t>);
Bytes frame(Type, std::uint64_t sequence, std::uint64_t timestamp_us, std::span<const std::uint8_t> payload={}, std::uint16_t minor=0);
// Provisional right-handed Z-up KCD basis -> Minecraft Y-up basis.
// Origin is subtracted BEFORE conversion; scale is blocks per KCD unit.
// Axes must be confirmed in the live game before flags bit 2 (calibrated) is set.
Vec3 to_minecraft(Vec3 kcd, Vec3 origin, double scale);
Vec3 to_kcd(Vec3 minecraft, Vec3 origin, double scale);
Quaternion to_minecraft(Quaternion camera_to_kcd);
Quaternion to_kcd(Quaternion camera_to_minecraft);
}
