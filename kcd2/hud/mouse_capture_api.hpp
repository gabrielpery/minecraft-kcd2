#pragma once
// Original shared ABI for the pinned MineCome ReShade build. No game APIs.
#include <cstdint>
#if defined(_WIN32)
#define MINECOME_MOUSE_CALL __stdcall
#else
#define MINECOME_MOUSE_CALL
#endif
namespace minecome::mouse {
constexpr std::uint32_t api_version=1,max_lease_ms=100;
enum class Result:std::uint32_t {ok,bad_argument,busy,unavailable,foreign_owner,draining};
enum class Reason:std::uint32_t {none,no_device,unsupported_device,layout,axis_mode,cooperative_window,foreground,capacity,configuration_changed,drain_failed,lock_contention,lease_expired,released,device_removed};
enum Flag:std::uint32_t {eligible=1,active=2,draining=4};
struct Snapshot {
    std::uint32_t size=sizeof(Snapshot),version=api_version,flags=0,reason=0,device_count=0,eligible_devices=0;
    std::uint64_t generation=0,token=0,lease_remaining_ms=0,state_suppressions=0,data_suppressions=0,peek_suppressions=0,queue_drains=0,drain_failures=0;
};
// Window is an HWND represented without importing Windows headers. Query permits
// token0 for capability inspection; request/release require the same nonzero token.
// Each call initializes Snapshot on success. A non-ok return never grants input
// ownership. Calls are nonblocking and never invoke a DirectInput COM method.
struct Api {
    std::uint32_t size=sizeof(Api),version=api_version;
    Result (MINECOME_MOUSE_CALL *query)(std::uintptr_t window,std::uint64_t token,Snapshot *out)=nullptr;
    Result (MINECOME_MOUSE_CALL *request)(std::uintptr_t window,std::uint64_t token,std::uint32_t lease_ms,Snapshot *out)=nullptr;
    Result (MINECOME_MOUSE_CALL *release)(std::uintptr_t window,std::uint64_t token,Snapshot *out)=nullptr;
};
using GetApi=const Api *(MINECOME_MOUSE_CALL *)(std::uint32_t version,std::uint32_t size);
static_assert(sizeof(Snapshot)==88);
} // namespace minecome::mouse
