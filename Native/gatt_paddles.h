#pragma once
#include <Windows.h>
#include <cstdint>

namespace xb_gatt {
// buttons は物理 P1-P4 の nibble。SDK の左右 enum への変換は bridge が担当する。
struct Sample {
    std::uint8_t buttons{}, pressed{}, released{};
    bool received{};
    HRESULT error{S_OK};
};
HRESULT Initialize() noexcept;
void Attach(std::uint64_t token, GUID container) noexcept;
void Detach(std::uint64_t token) noexcept;
Sample Poll(std::uint64_t token) noexcept;
void Resync() noexcept;
// 10秒以内に終了しなければ資源を保持し、次の呼び出しで再試行する。
HRESULT Shutdown() noexcept;
#ifdef XB_GATT_TEST
bool TestAccumulator() noexcept;
#endif
}
