#include "bridge.cpp"
#include <array>
#include <wrl/implements.h>
#include <cstdio>
#include <cstdlib>
#include <limits>

using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;
using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::Make;

namespace {
void Check(bool condition, const char* name) {
    if (!condition) { std::fprintf(stderr, "FAIL: %s\n", name); std::exit(1); }
}

class Reading final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInputReading> {
public:
    std::uint64_t timestamp{};
    GameInputGamepadState state{};
    bool valid{true};
    GameInputKind STDMETHODCALLTYPE GetInputKind() override { return GameInputKindGamepad; }
    std::uint64_t STDMETHODCALLTYPE GetTimestamp() override { return timestamp; }
    void STDMETHODCALLTYPE GetDevice(IGameInputDevice** output) override { *output = nullptr; }
    std::uint32_t STDMETHODCALLTYPE GetControllerAxisCount() override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerAxisState(std::uint32_t, float*) override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerButtonCount() override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerButtonState(std::uint32_t, bool*) override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerSwitchCount() override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerSwitchState(std::uint32_t, GameInputSwitchPosition*) override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetKeyCount() override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetKeyState(std::uint32_t, GameInputKeyState*) override { return 0; }
    bool STDMETHODCALLTYPE GetMouseState(GameInputMouseState*) override { return false; }
    bool STDMETHODCALLTYPE GetSensorsState(GameInputSensorsState*) override { return false; }
    bool STDMETHODCALLTYPE GetArcadeStickState(GameInputArcadeStickState*) override { return false; }
    bool STDMETHODCALLTYPE GetFlightStickState(GameInputFlightStickState*) override { return false; }
    bool STDMETHODCALLTYPE GetGamepadState(GameInputGamepadState* output) override { *output = state; return valid; }
    bool STDMETHODCALLTYPE GetRacingWheelState(GameInputRacingWheelState*) override { return false; }
    bool STDMETHODCALLTYPE GetRawReport(IGameInputRawDeviceReport**) override { return false; }
};

class Input final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInput> {
public:
    ComPtr<IGameInputReading> latest;
    std::vector<ComPtr<IGameInputReading>> history;
    std::uint64_t clock{100};
    HRESULT tail{GAMEINPUT_E_READING_NOT_FOUND};
    bool unregisterSucceeds{true}, unregisterUnlocked{true};
    unsigned unregisterCalls{}, currentCalls{};
    std::uint64_t STDMETHODCALLTYPE GetCurrentTimestamp() override { return clock; }
    HRESULT STDMETHODCALLTYPE GetCurrentReading(GameInputKind, IGameInputDevice*, IGameInputReading** output) override {
        ++currentCalls;
        if (!latest) { *output = nullptr; return E_FAIL; }
        return latest.CopyTo(output);
    }
    HRESULT STDMETHODCALLTYPE GetNextReading(IGameInputReading* reference, GameInputKind, IGameInputDevice*, IGameInputReading** output) override {
        *output = nullptr;
        std::size_t index{};
        for (std::size_t i = 0; i < history.size(); ++i)
            if (history[i].Get() == reference) { index = i + 1; break; }
        if (index == history.size()) return tail;
        return history[index].CopyTo(output);
    }
    HRESULT STDMETHODCALLTYPE GetPreviousReading(IGameInputReading*, GameInputKind, IGameInputDevice*, IGameInputReading**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE RegisterReadingCallback(IGameInputDevice*, GameInputKind, void*, GameInputReadingCallback, GameInputCallbackToken*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE RegisterDeviceCallback(IGameInputDevice*, GameInputKind, GameInputDeviceStatus, GameInputEnumerationKind, void*, GameInputDeviceCallback, GameInputCallbackToken*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE RegisterSystemButtonCallback(IGameInputDevice*, GameInputSystemButtons, void*, GameInputSystemButtonCallback, GameInputCallbackToken*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE RegisterKeyboardLayoutCallback(IGameInputDevice*, void*, GameInputKeyboardLayoutCallback, GameInputCallbackToken*) override { return E_NOTIMPL; }
    void STDMETHODCALLTYPE StopCallback(GameInputCallbackToken) override {}
    bool STDMETHODCALLTYPE UnregisterCallback(GameInputCallbackToken) override {
        ++unregisterCalls;
        for (const auto& device : context->devices)
            Check(!device.ownsRumble, "owned output stopped before callback unregister");
        if (context->mutex.try_lock()) context->mutex.unlock();
        else unregisterUnlocked = false;
        return unregisterSucceeds;
    }
    HRESULT STDMETHODCALLTYPE CreateDispatcher(IGameInputDispatcher**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE FindDeviceFromId(const APP_LOCAL_DEVICE_ID*, IGameInputDevice**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE FindDeviceFromPlatformString(LPCWSTR, IGameInputDevice**) override { return E_NOTIMPL; }
    void STDMETHODCALLTYPE SetFocusPolicy(GameInputFocusPolicy) override {}
    HRESULT STDMETHODCALLTYPE CreateAggregateDevice(GameInputKind, APP_LOCAL_DEVICE_ID*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE DisableAggregateDevice(const APP_LOCAL_DEVICE_ID*) override { return E_NOTIMPL; }
};

class Hardware final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInputDevice> {
public:
    GameInputDeviceStatus status{GameInputDeviceConnected};
    GameInputRumbleParams lastRumble{};
    unsigned rumbleCalls{}, stopCalls{};
    GameInputDeviceInfo info{};
    GameInputGamepadInfo gamepad{};
    Hardware() {
        info.gamepadInfo = &gamepad;
        info.supportedInput = GameInputKindGamepad;
    }
    HRESULT STDMETHODCALLTYPE GetDeviceInfo(const GameInputDeviceInfo** output) override { *output = &info; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetHapticInfo(GameInputHapticInfo*) override { return E_NOTIMPL; }
    GameInputDeviceStatus STDMETHODCALLTYPE GetDeviceStatus() override { return status; }
    HRESULT STDMETHODCALLTYPE CreateForceFeedbackEffect(std::uint32_t, const GameInputForceFeedbackParams*, IGameInputForceFeedbackEffect**) override { return E_NOTIMPL; }
    bool STDMETHODCALLTYPE IsForceFeedbackMotorPoweredOn(std::uint32_t) override { return false; }
    void STDMETHODCALLTYPE SetForceFeedbackMotorGain(std::uint32_t, float) override {}
    void STDMETHODCALLTYPE SetRumbleState(const GameInputRumbleParams* params) override {
        ++rumbleCalls;
        lastRumble = params ? *params : GameInputRumbleParams{};
        if (!params || !(params->lowFrequency || params->highFrequency || params->leftTrigger || params->rightTrigger)) ++stopCalls;
    }
    HRESULT STDMETHODCALLTYPE DirectInputEscape(std::uint32_t, const void*, std::uint32_t, void*, std::uint32_t, std::uint32_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CreateInputMapper(IGameInputMapper**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraAxisCount(GameInputKind, std::uint32_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraButtonCount(GameInputKind, std::uint32_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraAxisIndexes(GameInputKind, std::uint32_t, std::uint8_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraButtonIndexes(GameInputKind, std::uint32_t, std::uint8_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CreateRawDeviceReport(std::uint32_t, GameInputRawDeviceReportKind, IGameInputRawDeviceReport**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SendRawDeviceOutput(IGameInputRawDeviceReport*) override { return E_NOTIMPL; }
};

ComPtr<Reading> Sample(std::uint64_t time, GameInputGamepadButtons buttons) {
    auto value = Make<Reading>();
    value->timestamp = time;
    value->state.buttons = buttons;
    return value;
}

ComPtr<Input> Setup() {
    Check(xb_shutdown() == S_OK, "fixture shutdown");
    auto input = Make<Input>();
    context = std::make_unique<Context>();
    context->input = input;
    Device device;
    device.state.token = 42;
    device.state.supported = static_cast<std::uint32_t>(standardButtons) | xb_guide | xb_share;
    device.reading = Sample(1, GameInputGamepadNone);
    context->devices.push_back(std::move(device));
    return input;
}

XbSnapshot Snapshot(std::int32_t* diagnostic = nullptr) {
    XbSnapshot value{};
    std::uint32_t count{};
    std::int32_t local{};
    Check(xb_poll(&value, 1, &count, &local) == S_OK && count == 1, "poll success");
    if (diagnostic) *diagnostic = local;
    return value;
}

}

int main() {
    Check(xb_initialize(xb_abi_version + 1, sizeof(XbSnapshot)) == E_INVALIDARG, "ABI version rejection");
    Check(xb_initialize(xb_abi_version, sizeof(XbSnapshot) - 1) == E_INVALIDARG, "ABI size rejection");
    std::uint32_t count = 9;
    std::int32_t diagnostic = E_FAIL;
    Check(xb_poll(nullptr, 0, &count, &diagnostic) == E_UNEXPECTED && count == 0, "missing initialization");
    Check(xb_poll(nullptr, 1, &count, &diagnostic) == E_INVALIDARG, "null output rejection");

    auto input = Setup();
    auto rumbleHardware = Make<Hardware>();
    context->devices[0].device = rumbleHardware;
    context->devices[0].state.rumble = GameInputRumbleLowFrequency | GameInputRumbleHighFrequency |
        GameInputRumbleLeftTrigger | GameInputRumbleRightTrigger;
    Check(xb_rumble(42, 0.1f, 0.2f, 0.3f, 0.4f) == S_OK &&
        rumbleHardware->lastRumble.lowFrequency == 0.1f && rumbleHardware->lastRumble.highFrequency == 0.2f &&
        rumbleHardware->lastRumble.leftTrigger == 0.3f && rumbleHardware->lastRumble.rightTrigger == 0.4f,
        "four motor parameters retain official semantics");
    const auto writes = rumbleHardware->rumbleCalls;
    Check(xb_rumble(42, std::numeric_limits<float>::quiet_NaN(), 0, 0, 0) == E_INVALIDARG &&
        xb_rumble(42, 0, std::numeric_limits<float>::infinity(), 0, 0) == E_INVALIDARG &&
        xb_rumble(99, 1, 0, 0, 0) == GAMEINPUT_E_DEVICE_NOT_FOUND && rumbleHardware->rumbleCalls == writes,
        "invalid values and stale tokens do not write");
    for (std::uint32_t mask = 0; mask < 16; ++mask) {
        context->devices[0].state.rumble = mask;
        for (unsigned motor = 0; motor < 4; ++motor) {
            float levels[4]{}; levels[motor] = 0.25f;
            auto before = rumbleHardware->rumbleCalls;
            auto result = xb_rumble(42, levels[0], levels[1], levels[2], levels[3]);
            Check((mask & (1u << motor)) ? result == S_OK && rumbleHardware->rumbleCalls == before + 1 :
                result == GAMEINPUT_E_FEEDBACK_NOT_SUPPORTED && rumbleHardware->rumbleCalls == before,
                "every motor capability combination is enforced");
        }
    }
    context->devices[0].state.rumble = GameInputRumbleLowFrequency;
    Check(xb_rumble(42, 2, -1, -2, -3) == S_OK && rumbleHardware->lastRumble.lowFrequency == 1 &&
        rumbleHardware->lastRumble.highFrequency == 0 && rumbleHardware->lastRumble.leftTrigger == 0 &&
        rumbleHardware->lastRumble.rightTrigger == 0, "clamp precedes unsupported motor validation");
    Check(xb_rumble(42, 0, 1, 0, 0) == GAMEINPUT_E_FEEDBACK_NOT_SUPPORTED && context->devices[0].ownsRumble,
        "rejected request preserves owned output");
    xb_resync();
    Check(context->devices[0].ownsRumble, "focus resync itself preserves rumble ownership");
    input->latest = Sample(5, GameInputGamepadNone);
    Snapshot();
    Check(context->devices[0].ownsRumble, "benign read preserves rumble");
    input->tail = GAMEINPUT_E_REFERENCE_READING_TOO_OLD;
    input->latest = Sample(8, GameInputGamepadNone);
    Snapshot();
    Check(context->devices[0].ownsRumble && rumbleHardware->stopCalls == 0,
        "successful history resync preserves owned output");
    input->latest.Reset();
    Snapshot();
    Check(!context->devices[0].ownsRumble && rumbleHardware->stopCalls == 1,
        "failed history resync stops output exactly once");
    input->tail = E_FAIL;
    Snapshot();
    Check(!context->devices[0].ownsRumble && rumbleHardware->stopCalls == 1, "fatal read stops owned output");
    Check(xb_rumble(42, 1, 0, 0, 0) == S_OK, "restart only by explicit valid request");
    rumbleHardware->status = GameInputDeviceNoStatus;
    Check(xb_rumble(42, 1, 0, 0, 0) == GAMEINPUT_E_DEVICE_NOT_FOUND && !context->devices[0].ownsRumble,
        "live disconnect status rejects output before delayed callback");
    rumbleHardware->status = GameInputDeviceConnected;
    Check(xb_rumble(42, 1, 0, 0, 0) == S_OK, "connected output");
    DeviceChanged(0, context.get(), rumbleHardware.Get(), 0, GameInputDeviceNoStatus, GameInputDeviceConnected);
    Check(context->devices.empty() && rumbleHardware->stopCalls == 3, "disconnect stops before erasing ownership");
    Check(xb_shutdown() == S_OK, "empty rumble fixture shutdown");

    input = Setup();
    context->devices[0].device = rumbleHardware;
    auto stops = rumbleHardware->stopCalls;
    Check(xb_shutdown() == S_OK && rumbleHardware->stopCalls == stops, "unowned output is untouched");
    input = Setup();
    context->devices[0].device = rumbleHardware;
    context->devices[0].state.rumble = GameInputRumbleLowFrequency;
    Check(xb_rumble(42, 1, 0, 0, 0) == S_OK, "owned shutdown fixture");
    context->deviceCallback = 11;
    input->unregisterSucceeds = false;
    Check(xb_shutdown() == E_FAIL && rumbleHardware->stopCalls == stops + 1 && !context->devices[0].ownsRumble,
        "failed unregister already stopped owned output");
    input->unregisterSucceeds = true;
    Check(xb_shutdown() == S_OK && rumbleHardware->stopCalls == stops + 1, "shutdown retry does not repeat stop");

    input = Setup();
    input->history = {Sample(2, GameInputGamepadA), Sample(3, GameInputGamepadNone)};
    auto value = Snapshot();
    Check(value.buttons == 0 && value.pressed == GameInputGamepadA && value.released == GameInputGamepadA,
        "short button press and release survive one poll");
    value = Snapshot();
    Check(value.pressed == 0 && value.released == 0 && value.error == S_OK && input->currentCalls == 0,
        "no next reading preserves state without resync");

    input = Setup();
    const auto faceButtons = GameInputGamepadA | GameInputGamepadB
        | GameInputGamepadX | GameInputGamepadY;
    input->history = {Sample(20, faceButtons), Sample(120, GameInputGamepadNone)};
    value = Snapshot();
    Check(value.buttons == faceButtons && value.pressed == faceButtons && value.released == 0,
        "four simultaneous faceButtons and cutoff preserve future reading");
    input->clock = 200;
    value = Snapshot();
    Check(value.buttons == 0 && value.pressed == 0 && value.released == faceButtons,
        "future reading is consumed in next poll");

    input = Setup();
    context->devices.clear();
    auto hardware = Make<Hardware>();
    hardware->gamepad.supportedLayout = standardButtons;
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices.size() == 1 && context->devices[0].state.supported == standardButtons,
        "device capabilities use the standard gamepad layout");
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceConnected);
    Check(context->devices.size() == 1, "repeated connected callback does not duplicate a device");
    auto standardPress = Sample(50, GameInputGamepadA);
    standardPress->state.leftTrigger = 0.7f;
    standardPress->state.leftThumbstickX = 0.9f;
    input->latest = standardPress;
    value = Snapshot();
    Check(value.buttons == GameInputGamepadA && value.leftTrigger == 0.7f && value.leftX == 0.9f,
        "standard input requires no controller button report or mapper");

    input = Setup();
    input->tail = GAMEINPUT_E_REFERENCE_READING_TOO_OLD;
    input->latest = Sample(80, GameInputGamepadY);
    value = Snapshot();
    Check(value.buttons == GameInputGamepadY && value.pressed == 0 && value.released == 0
        && value.error == GAMEINPUT_E_REFERENCE_READING_TOO_OLD && value.timestamp == 80,
        "expired history resync has no invented edges");

    auto invalid = Sample(90, GameInputGamepadA);
    invalid->valid = false;
    input->latest = invalid;
    value = Snapshot();
    Check(value.error == E_FAIL && value.buttons == 0 && value.pressed == 0 && value.released == 0
        && value.timestamp == 0 && value.token == 42 && !context->devices[0].reading,
        "invalid gamepad resync neutralizes stale state");

    input = Setup();
    context->callbackError = E_OUTOFMEMORY;
    input->history = {Sample(2, GameInputGamepadA)};
    value = Snapshot(&diagnostic);
    Check(diagnostic == E_OUTOFMEMORY && value.buttons == GameInputGamepadA && value.error == S_OK,
        "callback diagnostic does not stop existing device reads");

    input = Setup();
    auto& device = context->devices[0];
    device.system = device.systemPressed = xb_guide;
    device.systemReleased = xb_share;
    xb_resync();
    input->latest = Sample(10, GameInputGamepadNone);
    value = Snapshot();
    Check(value.buttons == xb_guide && value.pressed == 0 && value.released == 0,
        "resync preserves held system button and clears old edges");

    input = Setup();
    context->deviceCallback = 11;
    context->systemCallback = 12;
    auto* retained = context.get();
    input->unregisterSucceeds = false;
    Check(xb_shutdown() == E_FAIL && context.get() == retained && context->stopping,
        "failed unregister retains callback context");
    input->unregisterSucceeds = true;
    Check(xb_shutdown() == S_OK && !context && input->unregisterCalls == 3 && input->unregisterUnlocked,
        "shutdown retry unregisters both callbacks outside mutex");
    Check(xb_shutdown() == S_OK, "shutdown is idempotent");

    input = Setup();
    context->devices.clear();
    auto firstHardware = Make<Hardware>();
    auto secondHardware = Make<Hardware>();
    for (auto pairHardware : {firstHardware.Get(), secondHardware.Get()}) {
        pairHardware->gamepad.supportedLayout = GameInputGamepadA;
        pairHardware->info.supportedRumbleMotors = GameInputRumbleLowFrequency;
        DeviceChanged(0, context.get(), pairHardware, 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    }
    Check(context->devices.size() == 2, "two native devices enumerate independently");
    const auto firstToken = context->devices[0].state.token;
    const auto secondToken = context->devices[1].state.token;
    Check(firstToken != secondToken, "native device tokens are distinct");
    XbSnapshot pair[2]{};
    Check(xb_poll(pair, 1, &count, &diagnostic) == HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER)
        && count == 2 && !context->devices[0].reading && !context->devices[1].reading,
        "capacity negotiation does not consume either device history");
    auto pairReading = Sample(10, GameInputGamepadA);
    input->latest = pairReading;
    Check(xb_poll(pair, 2, &count, &diagnostic) == S_OK && count == 2
        && pair[0].token == firstToken && pair[1].token == secondToken
        && pair[0].buttons == GameInputGamepadA && pair[1].buttons == GameInputGamepadA,
        "resized native output preserves both device identities");
    Check(xb_rumble(firstToken, 0.25f, 0, 0, 0) == S_OK && firstHardware->rumbleCalls == 1
        && secondHardware->rumbleCalls == 0, "output ownership remains device-specific");
    DeviceChanged(0, context.get(), firstHardware.Get(), 0, GameInputDeviceNoStatus, GameInputDeviceConnected);
    Check(context->devices.size() == 1 && context->devices[0].state.token == secondToken
        && firstHardware->stopCalls == 1 && secondHardware->stopCalls == 0,
        "disconnect neutralizes only owned first device output");
    Check(xb_rumble(firstToken, 0.25f, 0, 0, 0) == GAMEINPUT_E_DEVICE_NOT_FOUND,
        "retired native token cannot control a remaining device");
    DeviceChanged(0, context.get(), firstHardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices.size() == 2 && context->devices[1].state.token != firstToken
        && context->devices[1].state.token != secondToken, "reconnection allocates a new native token");
    Check(xb_shutdown() == S_OK, "multiple native device shutdown");
    std::puts("Native regression tests passed (fake GameInput; no hardware).");
    return 0;
}
