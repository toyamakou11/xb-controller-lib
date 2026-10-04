#include "bridge.h"
#include <Windows.h>
#include <GameInput.h>
#include <wrl/client.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <mutex>
#include <vector>

using namespace GameInput::v3;
using Microsoft::WRL::ComPtr;

namespace {
constexpr std::array<GameInputGamepadButtons, 4> paddleButtons{
    GameInputGamepadPaddleLeft1, GameInputGamepadPaddleLeft2,
    GameInputGamepadPaddleRight1, GameInputGamepadPaddleRight2};
constexpr std::array<GameInputGamepadButtons, 26> standardButtons{
    GameInputGamepadMenu, GameInputGamepadView, GameInputGamepadA, GameInputGamepadB,
    GameInputGamepadX, GameInputGamepadY, GameInputGamepadC, GameInputGamepadZ,
    GameInputGamepadDPadUp, GameInputGamepadDPadDown, GameInputGamepadDPadLeft, GameInputGamepadDPadRight,
    GameInputGamepadLeftShoulder, GameInputGamepadRightShoulder,
    GameInputGamepadLeftThumbstick, GameInputGamepadRightThumbstick,
    GameInputGamepadLeftTriggerButton, GameInputGamepadRightTriggerButton,
    GameInputGamepadLeftThumbstickUp, GameInputGamepadLeftThumbstickDown,
    GameInputGamepadLeftThumbstickLeft, GameInputGamepadLeftThumbstickRight,
    GameInputGamepadRightThumbstickUp, GameInputGamepadRightThumbstickDown,
    GameInputGamepadRightThumbstickLeft, GameInputGamepadRightThumbstickRight};
struct RawButton { std::uint32_t mask, index; };
struct Device {
    ComPtr<IGameInputDevice> device;
    ComPtr<IGameInputReading> reading;
    XbSnapshot state{};
    std::uint64_t system{}, systemPressed{}, systemReleased{};
    std::vector<RawButton> rawMappings;
    std::unique_ptr<bool[]> rawButtons;
    std::uint32_t rawCount{}, rawMask{};
    bool ownsRumble{};
};
struct Context {
    ComPtr<IGameInput> input;
    GameInputCallbackToken deviceCallback{}, systemCallback{};
    std::mutex mutex;
    std::vector<Device> devices;
    bool stopping{};
    HRESULT callbackError{S_OK};
};
// 公開関数は Unity のメインスレッド専用。callback だけが別スレッドで動く。
std::unique_ptr<Context> context;
std::uint64_t nextToken = 1;

std::uint64_t SystemMask(GameInputSystemButtons buttons) noexcept {
    std::uint64_t result{};
    if (buttons & GameInputSystemButtonGuide) result |= xb_guide;
    if (buttons & GameInputSystemButtonShare) result |= xb_share;
    return result;
}

void CALLBACK DeviceChanged(GameInputCallbackToken, void* data, IGameInputDevice* device,
    std::uint64_t, GameInputDeviceStatus current, GameInputDeviceStatus) noexcept {
    auto& c = *static_cast<Context*>(data);
    try {
        std::lock_guard<std::mutex> lock(c.mutex);
        if (c.stopping) return;
        auto found = std::find_if(c.devices.begin(), c.devices.end(),
            [device](const Device& value) { return value.device.Get() == device; });
        if (!(current & GameInputDeviceConnected)) {
            if (found != c.devices.end()) c.devices.erase(found);
            return;
        }
        if (found != c.devices.end()) return;
        const GameInputDeviceInfo* info{};
        auto hr = device->GetDeviceInfo(&info);
        if (FAILED(hr)) { c.callbackError = hr; return; }
        if (!info || !info->gamepadInfo) return;
        Device entry;
        entry.device = device;
        entry.state.token = nextToken++;
        entry.state.supported = static_cast<std::uint32_t>(info->gamepadInfo->supportedLayout)
            | SystemMask(info->supportedSystemButtons);
        entry.state.rumble = static_cast<std::uint32_t>(info->supportedRumbleMotors);
        if (info->controllerInfo && (info->supportedInput & GameInputKindControllerButton)) {
            ComPtr<IGameInputMapper> mapper;
            if (SUCCEEDED(device->CreateInputMapper(&mapper))) {
                for (auto paddle : paddleButtons) {
                    GameInputButtonMapping mapping{};
                    if (mapper->GetGamepadButtonMappingInfo(paddle, &mapping)
                        && mapping.controllerElementKind == GameInputElementKindButton
                        && mapping.controllerIndex < info->controllerInfo->controllerButtonCount)
                        entry.rawMappings.push_back({static_cast<std::uint32_t>(paddle), mapping.controllerIndex});
                }
                // 重複 index を独立入力として公開しない。観測した実機番号は使用しない。
                std::uint32_t duplicateMask{};
                for (std::size_t i = 0; i < entry.rawMappings.size(); ++i)
                    for (std::size_t j = i + 1; j < entry.rawMappings.size(); ++j)
                        if (entry.rawMappings[i].index == entry.rawMappings[j].index)
                            duplicateMask |= entry.rawMappings[i].mask | entry.rawMappings[j].mask;
                for (auto standard : standardButtons) {
                    GameInputButtonMapping mapping{};
                    if (!mapper->GetGamepadButtonMappingInfo(standard, &mapping)
                        || mapping.controllerElementKind != GameInputElementKindButton) continue;
                    for (const auto& paddle : entry.rawMappings)
                        if (paddle.index == mapping.controllerIndex) duplicateMask |= paddle.mask;
                }
                if (duplicateMask) {
                    entry.state.supported &= ~static_cast<std::uint64_t>(duplicateMask);
                    c.callbackError = HRESULT_FROM_WIN32(ERROR_INVALID_DATA);
                    entry.rawMappings.erase(std::remove_if(entry.rawMappings.begin(), entry.rawMappings.end(),
                        [duplicateMask](const RawButton& mapping) { return (mapping.mask & duplicateMask) != 0; }), entry.rawMappings.end());
                }
                if (!entry.rawMappings.empty()) {
                    entry.rawCount = info->controllerInfo->controllerButtonCount;
                    entry.rawButtons = std::make_unique<bool[]>(entry.rawCount);
                    for (const auto& mapping : entry.rawMappings) entry.rawMask |= mapping.mask;
                    entry.state.supported |= entry.rawMask;
                }
            }
        }
        c.devices.push_back(std::move(entry));
    } catch (...) {
        std::lock_guard<std::mutex> lock(c.mutex);
        c.callbackError = E_OUTOFMEMORY;
    }
}

void CALLBACK SystemChanged(GameInputCallbackToken, void* data, IGameInputDevice* device,
    std::uint64_t, GameInputSystemButtons current, GameInputSystemButtons) noexcept {
    auto& c = *static_cast<Context*>(data);
    std::lock_guard<std::mutex> lock(c.mutex);
    if (c.stopping) return;
    for (auto& entry : c.devices) {
        if (entry.device.Get() != device) continue;
        auto value = SystemMask(current);
        entry.systemPressed |= value & ~entry.system;
        entry.systemReleased |= entry.system & ~value;
        entry.system = value;
        break;
    }
}

bool Apply(Device& entry, IGameInputReading* reading, bool edges) noexcept {
    GameInputGamepadState value{};
    if (!reading->GetGamepadState(&value)) return false;
    auto buttons = static_cast<std::uint32_t>(value.buttons) & entry.state.supported;
    if (!entry.rawMappings.empty()) {
        const auto returned = reading->GetControllerButtonState(entry.rawCount, entry.rawButtons.get());
        // 両状態が取得できてから commit する。部分成功で古い値やエッジを残さない。
        buttons &= ~static_cast<std::uint64_t>(entry.rawMask);
        for (const auto& mapping : entry.rawMappings) {
            if (mapping.index >= returned) return false;
            if (entry.rawButtons[mapping.index]) buttons |= mapping.mask;
        }
    }
    if (edges) {
        entry.state.pressed |= buttons & ~entry.state.buttons;
        entry.state.released |= entry.state.buttons & ~buttons & 0xFFFFFFFFull;
    }
    entry.state.buttons = buttons;
    entry.state.timestamp = reading->GetTimestamp();
    entry.state.leftTrigger = value.leftTrigger;
    entry.state.rightTrigger = value.rightTrigger;
    entry.state.leftX = value.leftThumbstickX;
    entry.state.leftY = value.leftThumbstickY;
    entry.state.rightX = value.rightThumbstickX;
    entry.state.rightY = value.rightThumbstickY;
    entry.state.error = S_OK;
    return true;
}

void Neutral(Device& entry, HRESULT error) noexcept {
    const auto token = entry.state.token;
    const auto supported = entry.state.supported;
    const auto rumble = entry.state.rumble;
    entry.state = {};
    entry.state.token = token;
    entry.state.supported = supported;
    entry.state.rumble = rumble;
    entry.state.error = error;
    entry.reading.Reset();
}

void Poll(Context& c, Device& entry, std::uint64_t cutoff) noexcept {
    entry.state.pressed = entry.state.released = 0;
    // 前回合成した system bit は gamepad 比較の対象から除く。
    entry.state.buttons &= 0xFFFFFFFFull;
    if (!entry.reading) {
        ComPtr<IGameInputReading> latest;
        auto hr = c.input->GetCurrentReading(GameInputKindGamepad, entry.device.Get(), &latest);
        if (FAILED(hr)) { Neutral(entry, hr); return; }
        if (!Apply(entry, latest.Get(), false)) { Neutral(entry, E_FAIL); return; }
        entry.reading = std::move(latest);
    } else {
        for (;;) {
            ComPtr<IGameInputReading> next;
            auto hr = c.input->GetNextReading(entry.reading.Get(), GameInputKindGamepad, entry.device.Get(), &next);
            if (hr == GAMEINPUT_E_READING_NOT_FOUND) break;
            if (hr == GAMEINPUT_E_REFERENCE_READING_TOO_OLD) {
                ComPtr<IGameInputReading> latest;
                auto latestHr = c.input->GetCurrentReading(GameInputKindGamepad, entry.device.Get(), &latest);
                if (FAILED(latestHr)) { Neutral(entry, latestHr); return; }
                // 失われた区間の押下/解放は推測せず、再同期を診断に残す。
                entry.state.pressed = entry.state.released = 0;
                if (!Apply(entry, latest.Get(), false)) { Neutral(entry, E_FAIL); return; }
                entry.state.error = hr;
                entry.reading = std::move(latest);
                break;
            }
            if (FAILED(hr)) { Neutral(entry, hr); return; }
            if (next->GetTimestamp() > cutoff) break;
            if (!Apply(entry, next.Get(), true)) { Neutral(entry, E_FAIL); return; }
            entry.reading = std::move(next);
        }
    }
    entry.state.buttons |= entry.system;
    entry.state.pressed |= entry.systemPressed;
    entry.state.released |= entry.systemReleased;
    entry.systemPressed = entry.systemReleased = 0;
}
}

std::int32_t __cdecl xb_initialize(std::uint32_t version, std::uint32_t size) noexcept {
    if (version != xb_abi_version || size != sizeof(XbSnapshot)) return E_INVALIDARG;
    auto old = xb_shutdown();
    if (FAILED(old)) return old;
    try {
        context = std::make_unique<Context>();
        auto& c = *context;
        auto hr = GameInputCreate(&c.input);
        if (FAILED(hr)) { context.reset(); return hr; }
        // 接続列挙をフォーカスから分離する。ゲームへの公開は C# 側でフォーカスを守る。
        c.input->SetFocusPolicy(GameInputEnableBackgroundInput);
        // blocking enumeration は callback を呼ぶため、ここで mutex を取得しない。
        hr = c.input->RegisterDeviceCallback(nullptr, GameInputKindGamepad, GameInputDeviceConnected,
            GameInputBlockingEnumeration, &c, DeviceChanged, &c.deviceCallback);
        if (SUCCEEDED(hr)) hr = c.input->RegisterSystemButtonCallback(nullptr,
            GameInputSystemButtonGuide | GameInputSystemButtonShare, &c, SystemChanged, &c.systemCallback);
        if (FAILED(hr)) { xb_shutdown(); return hr; }
        return S_OK;
    } catch (...) { xb_shutdown(); return E_OUTOFMEMORY; }
}

std::int32_t __cdecl xb_shutdown() noexcept {
    if (!context) return S_OK;
    auto& c = *context;
    {
        std::lock_guard<std::mutex> lock(c.mutex);
        c.stopping = true;
    }
    // 解除の待機中に mutex を保持しない。失敗時は callback の資源を保持する。
    if (c.deviceCallback && !c.input->UnregisterCallback(c.deviceCallback)) return E_FAIL;
    c.deviceCallback = 0;
    if (c.systemCallback && !c.input->UnregisterCallback(c.systemCallback)) return E_FAIL;
    c.systemCallback = 0;
    for (auto& entry : c.devices) if (entry.ownsRumble) entry.device->SetRumbleState(nullptr);
    context.reset();
    return S_OK;
}

std::int32_t __cdecl xb_poll(XbSnapshot* buffer, std::uint32_t capacity, std::uint32_t* count, std::int32_t* diagnostic) noexcept {
    if (!count || !diagnostic || (capacity && !buffer)) return E_INVALIDARG;
    *count = 0;
    *diagnostic = S_OK;
    if (!context || context->stopping) return E_UNEXPECTED;
    auto& c = *context;
    std::lock_guard<std::mutex> lock(c.mutex);
    *count = static_cast<std::uint32_t>(c.devices.size());
    *diagnostic = c.callbackError;
    if (capacity < *count) return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
    const auto cutoff = c.input->GetCurrentTimestamp();
    for (std::uint32_t i = 0; i < *count; ++i) {
        Poll(c, c.devices[i], cutoff);
        buffer[i] = c.devices[i].state;
    }
    // callback 診断は正常な既存端末の読み取りを止めない。
    return S_OK;
}

std::int32_t __cdecl xb_rumble(std::uint64_t token, float low, float high, float left, float right) noexcept {
    if (!std::isfinite(low) || !std::isfinite(high) || !std::isfinite(left) || !std::isfinite(right)) return E_INVALIDARG;
    if (!context || context->stopping) return E_UNEXPECTED;
    std::lock_guard<std::mutex> lock(context->mutex);
    for (auto& entry : context->devices) {
        if (entry.state.token != token) continue;
        const float values[] = {low, high, left, right};
        for (unsigned i = 0; i < 4; ++i)
            if (values[i] != 0 && !(entry.state.rumble & (1u << i))) return GAMEINPUT_E_FEEDBACK_NOT_SUPPORTED;
        GameInputRumbleParams params{std::clamp(low, 0.0f, 1.0f), std::clamp(high, 0.0f, 1.0f),
            std::clamp(left, 0.0f, 1.0f), std::clamp(right, 0.0f, 1.0f)};
        entry.device->SetRumbleState(&params);
        entry.ownsRumble = params.lowFrequency || params.highFrequency || params.leftTrigger || params.rightTrigger;
        return S_OK;
    }
    return GAMEINPUT_E_DEVICE_NOT_FOUND;
}

void __cdecl xb_resync() noexcept {
    if (!context) return;
    std::lock_guard<std::mutex> lock(context->mutex);
    for (auto& entry : context->devices) {
        Neutral(entry, S_OK);
        entry.systemPressed = entry.systemReleased = 0;
    }
}
