#pragma once
// Original ABI v2 for the separate pinned selective-capture ReShade runtime.
#include <cstdint>
#include <cstddef>
#if defined(_WIN32)
#define MINECOME_SELECTIVE_CALL __stdcall
#else
#define MINECOME_SELECTIVE_CALL
#endif
namespace minecome::selective {
constexpr std::uint32_t api_version=2,max_lease_ms=100;
enum class Mode:std::uint32_t {none=0,full=1,buttons=2};
enum class Result:std::uint32_t {ok,bad_argument,busy,unavailable,foreign_owner,draining};
enum class Reason:std::uint32_t {none,no_device,unsupported_device,layout,axis_mode,cooperative_window,foreground,capacity,configuration_changed,drain_failed,lock_contention,lease_expired,released,device_removed,mode_changed,buffer_capacity,concurrent_io};
enum Flag:std::uint32_t {eligible=1,active=2,draining=4};
struct Snapshot {
    std::uint32_t size=sizeof(Snapshot),version=api_version,flags=0,reason=0,device_count=0,eligible_devices=0;
    std::uint64_t generation=0,token=0,lease_remaining_ms=0,state_suppressions=0,data_suppressions=0,peek_suppressions=0,queue_drains=0,drain_failures=0;
    Mode mode=Mode::none;std::uint32_t reserved=0;
    std::uint64_t axis_records_delivered=0,button_records_filtered=0,buffer_overflows=0;
};
struct Api {
    std::uint32_t size=sizeof(Api),version=api_version;
    Result (MINECOME_SELECTIVE_CALL *query)(std::uintptr_t window,std::uint64_t token,Snapshot *out)=nullptr;
    Result (MINECOME_SELECTIVE_CALL *request)(std::uintptr_t window,std::uint64_t token,std::uint32_t lease_ms,Mode mode,Snapshot *out)=nullptr;
    Result (MINECOME_SELECTIVE_CALL *release)(std::uintptr_t window,std::uint64_t token,Snapshot *out)=nullptr;
};
using GetApi=const Api *(MINECOME_SELECTIVE_CALL *)(std::uint32_t version,std::uint32_t size);
static_assert(offsetof(Snapshot,mode)==88&&sizeof(Snapshot)==120);
}
