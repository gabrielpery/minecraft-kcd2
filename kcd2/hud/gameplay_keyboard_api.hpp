#pragma once
// Original MineCome v5 ABI. Separate from the unchanged mouse API v2.
#include <cstdint>
#if defined(_WIN32)
#define MINECOME_GAMEPLAY_CALL __stdcall
#else
#define MINECOME_GAMEPLAY_CALL
#endif
namespace minecome::gameplay_keyboard {
constexpr std::uint32_t api_version=5,max_lease_ms=100;
enum class Mode:std::uint32_t {none=0,ui=1,full=2};
struct Api {
    std::uint32_t size=sizeof(Api),version=api_version;
    bool (MINECOME_GAMEPLAY_CALL *query)(std::uintptr_t window,std::uint64_t token)=nullptr;
    bool (MINECOME_GAMEPLAY_CALL *request)(std::uintptr_t window,std::uint64_t token,std::uint32_t lease_ms,Mode mode)=nullptr;
    bool (MINECOME_GAMEPLAY_CALL *release)(std::uintptr_t window,std::uint64_t token)=nullptr;
};
using GetApi=const Api *(MINECOME_GAMEPLAY_CALL *)(std::uint32_t,std::uint32_t);
}
