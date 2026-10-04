#include "bridge.cpp"
#define XB_RAW_PROBE_TEST
#include "raw_probe.cpp"
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
    std::vector<unsigned char> raw;
    bool valid{true};
    ComPtr<IGameInputRawDeviceReport> report;
    GameInputKind STDMETHODCALLTYPE GetInputKind() override { return GameInputKindGamepad; }
    std::uint64_t STDMETHODCALLTYPE GetTimestamp() override { return timestamp; }
    void STDMETHODCALLTYPE GetDevice(IGameInputDevice** output) override { *output = nullptr; }
    std::uint32_t STDMETHODCALLTYPE GetControllerAxisCount() override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerAxisState(std::uint32_t, float*) override { return 0; }
    std::uint32_t STDMETHODCALLTYPE GetControllerButtonCount() override { return static_cast<std::uint32_t>(raw.size()); }
    std::uint32_t STDMETHODCALLTYPE GetControllerButtonState(std::uint32_t capacity, bool* output) override {
        auto count = std::min(capacity, static_cast<std::uint32_t>(raw.size()));
        for (std::uint32_t i = 0; i < count; ++i) output[i] = raw[i] != 0;
        return count;
    }
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
    bool STDMETHODCALLTYPE GetRawReport(IGameInputRawDeviceReport** output) override {
        report.CopyTo(output); return report != nullptr;
    }
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

class Mapper final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInputMapper> {
public:
    std::array<GameInputButtonMapping, 4> mappings{};
    bool hasStandardMapping{};
    GameInputGamepadButtons standardButton{GameInputGamepadA};
    GameInputButtonMapping standardMapping{};
    bool STDMETHODCALLTYPE GetArcadeStickButtonMappingInfo(GameInputArcadeStickButtons, GameInputButtonMapping*) override { return false; }
    bool STDMETHODCALLTYPE GetFlightStickAxisMappingInfo(GameInputFlightStickAxes, GameInputAxisMapping*) override { return false; }
    bool STDMETHODCALLTYPE GetFlightStickButtonMappingInfo(GameInputFlightStickButtons, GameInputButtonMapping*) override { return false; }
    bool STDMETHODCALLTYPE GetGamepadAxisMappingInfo(GameInputGamepadAxes, GameInputAxisMapping*) override { return false; }
    bool STDMETHODCALLTYPE GetGamepadButtonMappingInfo(GameInputGamepadButtons button, GameInputButtonMapping* output) override {
        if (hasStandardMapping && button == standardButton) { *output = standardMapping; return true; }
        for (std::size_t i = 0; i < paddleButtons.size(); ++i)
            if (paddleButtons[i] == button) { *output = mappings[i]; return true; }
        return false;
    }
    bool STDMETHODCALLTYPE GetRacingWheelAxisMappingInfo(GameInputRacingWheelAxes, GameInputAxisMapping*) override { return false; }
    bool STDMETHODCALLTYPE GetRacingWheelButtonMappingInfo(GameInputRacingWheelButtons, GameInputButtonMapping*) override { return false; }
};

class Hardware final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInputDevice> {
public:
    GameInputDeviceStatus status{GameInputDeviceConnected};
    GameInputRumbleParams lastRumble{};
    unsigned rumbleCalls{}, stopCalls{};
    GameInputDeviceInfo info{};
    GameInputGamepadInfo gamepad{};
    GameInputControllerInfo controller{};
    ComPtr<Mapper> mapper{Make<Mapper>()};
    Hardware() {
        info.gamepadInfo = &gamepad;
        info.controllerInfo = &controller;
        info.supportedInput = GameInputKindGamepad | GameInputKindControllerButton;
        controller.controllerButtonCount = 12;
        const std::uint32_t indexes[] = {9, 2, 7, 4};
        for (std::size_t i = 0; i < paddleButtons.size(); ++i) {
            mapper->mappings[i].controllerElementKind = GameInputElementKindButton;
            mapper->mappings[i].controllerIndex = indexes[i];
        }
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
    HRESULT STDMETHODCALLTYPE CreateInputMapper(IGameInputMapper** output) override { return mapper.CopyTo(output); }
    HRESULT STDMETHODCALLTYPE GetExtraAxisCount(GameInputKind, std::uint32_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraButtonCount(GameInputKind, std::uint32_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraAxisIndexes(GameInputKind, std::uint32_t, std::uint8_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetExtraButtonIndexes(GameInputKind, std::uint32_t, std::uint8_t*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CreateRawDeviceReport(std::uint32_t, GameInputRawDeviceReportKind, IGameInputRawDeviceReport**) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE SendRawDeviceOutput(IGameInputRawDeviceReport*) override { return E_NOTIMPL; }
};

class RawReport final : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IGameInputRawDeviceReport> {
public:
    GameInputRawDeviceReportInfo info{GameInputRawInputReport, 7, 3};
    std::vector<unsigned char> bytes{0x10, 0x20, 0x30};
    bool shortCopy{};
    void STDMETHODCALLTYPE GetDevice(IGameInputDevice** output) override { *output = nullptr; }
    void STDMETHODCALLTYPE GetReportInfo(GameInputRawDeviceReportInfo* output) override { *output = info; }
    size_t STDMETHODCALLTYPE GetRawDataSize() override { return bytes.size(); }
    size_t STDMETHODCALLTYPE GetRawData(size_t capacity, void* output) override {
        auto length = std::min(capacity, bytes.size());
        if (shortCopy && length) --length;
        std::copy_n(bytes.data(), length, static_cast<unsigned char*>(output));
        return length;
    }
    bool STDMETHODCALLTYPE SetRawData(size_t, const void*) override { return false; }
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
    device.state.supported = 0xFFFFFFFFull | xb_guide | xb_share;
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

// 実機番号と異なる疎な index で、API 由来マッピングの読み取りを検証する。
void RawFixture() {
    auto& device = context->devices[0];
    device.rawCount = 12;
    device.rawButtons = std::make_unique<bool[]>(device.rawCount);
    const std::uint32_t indexes[] = {9, 2, 7, 4};
    for (std::size_t i = 0; i < paddleButtons.size(); ++i) {
        const auto mask = static_cast<std::uint32_t>(paddleButtons[i]);
        device.rawMappings.push_back({mask, indexes[i]});
        device.rawMask |= mask;
    }
}

ComPtr<Reading> RawSample(std::uint64_t time, GameInputGamepadButtons gamepad, unsigned rawPaddles) {
    auto reading = Sample(time, gamepad);
    reading->raw.resize(12);
    for (std::size_t i = 0; i < context->devices[0].rawMappings.size(); ++i)
        reading->raw[context->devices[0].rawMappings[i].index] = (rawPaddles & (1u << i)) ? 1 : 0;
    return reading;
}
}

int main() {
    auto rawReading = Make<Reading>();
    auto rawReport = Make<RawReport>();
    rawReading->report = rawReport;
    Report descriptor; descriptor.info = rawReport->info;
    descriptor.bytes.resize(3); descriptor.previous.resize(3);
    std::vector<Report> descriptors{descriptor};
    Check(Receive(rawReading.Get(), descriptors, 0) && descriptors[0].received &&
        descriptors[0].previous == rawReport->bytes, "raw exact receipt accepted without paddle inference");
    descriptors[0].received = false;
    rawReport->bytes.clear();
    Check(!Receive(rawReading.Get(), descriptors, 0) && !descriptors[0].received, "raw empty payload rejected despite nonzero descriptor");
    rawReport->bytes = {0x10, 0x20, 0x30}; rawReport->shortCopy = true;
    Check(!Receive(rawReading.Get(), descriptors, 0) && !descriptors[0].received, "raw partial copy never commits receipt");
    rawReport->shortCopy = false; rawReport->info.id++;
    Check(!Receive(rawReading.Get(), descriptors, 0), "unknown report id rejected");
    rawReport->info.id--; rawReport->info.kind = GameInputRawOutputReport;
    Check(!Receive(rawReading.Get(), descriptors, 0), "output report cannot masquerade as input");
    rawReading->report.Reset();
    Check(!Receive(rawReading.Get(), descriptors, 0), "missing report rejected");
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
    input->history = {Sample(2, GameInputGamepadPaddleLeft1), Sample(3, GameInputGamepadNone)};
    auto value = Snapshot();
    Check(value.buttons == 0 && value.pressed == GameInputGamepadPaddleLeft1 && value.released == GameInputGamepadPaddleLeft1,
        "short paddle press and release survive one poll");
    value = Snapshot();
    Check(value.pressed == 0 && value.released == 0 && value.error == S_OK && input->currentCalls == 0,
        "no next reading preserves state without resync");

    input = Setup();
    const auto paddles = GameInputGamepadPaddleLeft1 | GameInputGamepadPaddleLeft2
        | GameInputGamepadPaddleRight1 | GameInputGamepadPaddleRight2;
    input->history = {Sample(20, paddles), Sample(120, GameInputGamepadNone)};
    value = Snapshot();
    Check(value.buttons == paddles && value.pressed == paddles && value.released == 0,
        "four simultaneous paddles and cutoff preserve future reading");
    input->clock = 200;
    value = Snapshot();
    Check(value.buttons == 0 && value.pressed == 0 && value.released == paddles,
        "future reading is consumed in next poll");

    input = Setup();
    RawFixture();
    input->history = {RawSample(2, GameInputGamepadNone, 15)};
    value = Snapshot();
    Check(value.buttons == paddles && value.pressed == paddles && value.released == 0,
        "all four raw mappings produce independent simultaneous paddles");
    input->history.push_back(RawSample(3, paddles, 0));
    value = Snapshot();
    Check(value.buttons == 0 && value.pressed == 0 && value.released == paddles,
        "raw false overrides held gamepad paddle bits");
    for (std::size_t i = 0; i < paddleButtons.size(); ++i) {
        input->history.push_back(RawSample(4 + i * 2, GameInputGamepadNone, 1u << i));
        input->history.push_back(RawSample(5 + i * 2, GameInputGamepadNone, 0));
        value = Snapshot();
        Check(value.buttons == 0 && value.pressed == paddleButtons[i] && value.released == paddleButtons[i],
            "each raw paddle short press produces only its own edges");
    }
    auto shortRaw = RawSample(30, GameInputGamepadA, 15);
    shortRaw->state.leftTrigger = 0.7f;
    shortRaw->state.leftThumbstickX = 0.9f;
    shortRaw->raw.resize(8); // 最初の保存 index 9 を含まない。
    input->history.push_back(RawSample(29, GameInputGamepadA, 15));
    input->history.push_back(shortRaw);
    value = Snapshot();
    Check(value.error == E_FAIL && value.buttons == 0 && value.pressed == 0 && value.released == 0
        && value.leftTrigger == 0 && value.leftX == 0 && value.timestamp == 0 && value.token == 42,
        "short raw result neutralizes whole snapshot including accumulated edges");

    input = Setup();
    context->devices.clear();
    auto hardware = Make<Hardware>();
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices.size() == 1 && context->devices[0].rawMappings.size() == 4
        && (context->devices[0].state.supported & paddles) == paddles,
        "device mapping discovers four paddles absent from supportedLayout");
    Check(context->devices[0].rawMappings[0].index == 9 && context->devices[0].rawMappings[1].index == 2,
        "device mapping preserves API indexes");

    context->devices.clear();
    hardware->gamepad.supportedLayout = paddles;
    hardware->mapper->mappings[1].controllerIndex = 9;
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    const auto duplicate = GameInputGamepadPaddleLeft1 | GameInputGamepadPaddleLeft2;
    Check(context->devices[0].rawMappings.size() == 2 && (context->devices[0].state.supported & duplicate) == 0
        && context->callbackError == HRESULT_FROM_WIN32(ERROR_INVALID_DATA),
        "duplicate indexes reject independent paddle claim even if layout advertises it");

    context->devices.clear();
    hardware = Make<Hardware>();
    hardware->mapper->mappings[0].controllerIndex = hardware->controller.controllerButtonCount;
    hardware->mapper->mappings[1].controllerElementKind = GameInputElementKindAxis;
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices[0].rawMappings.size() == 2 && (context->devices[0].rawMask & duplicate) == 0,
        "out of range and nonbutton mappings are not read as raw buttons");

    context->devices.clear();
    context->callbackError = S_OK;
    hardware = Make<Hardware>();
    hardware->gamepad.supportedLayout = paddles | GameInputGamepadA;
    hardware->mapper->hasStandardMapping = true;
    hardware->mapper->standardMapping.controllerElementKind = GameInputElementKindButton;
    hardware->mapper->standardMapping.controllerIndex = 9;
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices[0].rawMappings.size() == 3
        && !(context->devices[0].state.supported & GameInputGamepadPaddleLeft1)
        && (context->devices[0].state.supported & GameInputGamepadA)
        && context->callbackError == HRESULT_FROM_WIN32(ERROR_INVALID_DATA),
        "standard button raw index collision revokes paddle support and preserves A");
    auto standardPress = Sample(50, GameInputGamepadA | GameInputGamepadPaddleLeft1);
    standardPress->raw.resize(12);
    standardPress->raw[9] = 1;
    input->latest = standardPress;
    value = Snapshot();
    Check(value.buttons == GameInputGamepadA,
        "colliding standard raw button cannot masquerade as an independent paddle");

    context->devices.clear();
    context->callbackError = S_OK;
    hardware->mapper->standardMapping.controllerElementKind = GameInputElementKindAxis;
    DeviceChanged(0, context.get(), hardware.Get(), 0, GameInputDeviceConnected, GameInputDeviceNoStatus);
    Check(context->devices[0].rawMappings.size() == 4
        && (context->devices[0].state.supported & paddles) == paddles && context->callbackError == S_OK,
        "axis and button index namespaces do not create a false collision");

    input = Setup();
    input->tail = GAMEINPUT_E_REFERENCE_READING_TOO_OLD;
    input->latest = Sample(80, GameInputGamepadPaddleRight2);
    value = Snapshot();
    Check(value.buttons == GameInputGamepadPaddleRight2 && value.pressed == 0 && value.released == 0
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
    std::puts("Native regression tests passed (fake GameInput; no hardware).");
    return 0;
}
