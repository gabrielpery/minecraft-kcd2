#pragma once
#include <cstdint>
#if defined(_WIN32)
#define MINECOME_MOTION_CALL __stdcall
#else
#define MINECOME_MOTION_CALL
#endif
namespace minecome::motion {
constexpr std::uint32_t api_version=1;
// Monotonic process-lifetime observations, sampled read-only by the addon worker.
// These count callbacks/records, not unique physical movements or camera frames.
struct Snapshot {
    std::uint32_t size=sizeof(Snapshot),version=api_version;
    std::uint64_t state_xy_observed=0,state_xy_passed=0,window_moves_passed=0,raw_moves_passed=0,
        raw_mixed_blocked=0,raw_buffer_blocked=0,hook_motion_blocked=0;
};
using ReadDiagnostics=bool(MINECOME_MOTION_CALL *)(Snapshot *out);
static_assert(sizeof(Snapshot)==64);
}
