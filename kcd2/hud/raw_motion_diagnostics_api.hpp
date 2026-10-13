#pragma once
#include <cstdint>
#if defined(_WIN32)
#define MINECOME_RAW_MOTION_CALL __stdcall
#else
#define MINECOME_RAW_MOTION_CALL
#endif
namespace minecome::raw_motion {
inline constexpr std::uint32_t api_version=1;
struct Snapshot {
    std::uint32_t size=sizeof(Snapshot),version=api_version;
    std::uint64_t mouse_raw_packets_seen=0,registered_helper_candidates=0,helper_moves_passed=0,
        route_owner_rejected=0,packet_rejected=0;
};
static_assert(sizeof(Snapshot)==48);
using ReadDiagnostics=bool(MINECOME_RAW_MOTION_CALL *)(Snapshot *);
}
