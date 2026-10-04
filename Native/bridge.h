#pragma once
#include <cstdint>

// C# と共有する ABI。追加・変更時はバージョンも変更する。
constexpr std::uint32_t xb_abi_version = 1;
constexpr std::uint64_t xb_guide = 1ull << 32;
constexpr std::uint64_t xb_share = 1ull << 33;
#pragma pack(push, 8)
struct XbSnapshot {
    std::uint64_t token, timestamp, supported, buttons, pressed, released;
    std::uint32_t rumble;
    std::int32_t error;
    float leftTrigger, rightTrigger, leftX, leftY, rightX, rightY;
};
#pragma pack(pop)
static_assert(sizeof(XbSnapshot) == 80, "ABI size");

#define XB_API extern "C" __declspec(dllexport)
XB_API std::int32_t __cdecl xb_initialize(std::uint32_t version, std::uint32_t size) noexcept;
XB_API std::int32_t __cdecl xb_shutdown() noexcept;
XB_API std::int32_t __cdecl xb_poll(XbSnapshot* buffer, std::uint32_t capacity, std::uint32_t* count, std::int32_t* diagnostic) noexcept;
XB_API std::int32_t __cdecl xb_rumble(std::uint64_t token, float low, float high, float left, float right) noexcept;
XB_API void __cdecl xb_resync() noexcept;
