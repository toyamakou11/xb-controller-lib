// 公開 raw GIP の受信だけを診断する。出力命令・パドルの推測は行わない。
#include <Windows.h>
#include <GameInput.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <memory>
#include <vector>

using namespace GameInput::v3;
using Microsoft::WRL::ComPtr;
namespace {
struct Enumeration {
    ComPtr<IGameInput> input;
    std::mutex mutex;
    std::vector<ComPtr<IGameInputDevice>> devices;
    bool failed{};
};
void CALLBACK Connected(GameInputCallbackToken, void* data, IGameInputDevice* device,
    std::uint64_t, GameInputDeviceStatus status, GameInputDeviceStatus) noexcept {
    auto& enumeration = *static_cast<Enumeration*>(data);
    try {
        std::lock_guard<std::mutex> lock(enumeration.mutex);
        if (!(status & GameInputDeviceConnected)) return;
        if (std::none_of(enumeration.devices.begin(), enumeration.devices.end(),
            [device](const auto& candidate) { return candidate.Get() == device; })) enumeration.devices.emplace_back(device);
    } catch (...) {
        std::lock_guard<std::mutex> lock(enumeration.mutex);
        enumeration.failed = true;
    }
}
struct Report {
    GameInputRawDeviceReportInfo info{};
    std::vector<unsigned char> bytes, previous;
    bool received{};
};
bool Receive(IGameInputReading* reading, std::vector<Report>& reports, std::size_t connection) {
    ComPtr<IGameInputRawDeviceReport> raw;
    if (!reading->GetRawReport(&raw) || !raw) {
        std::printf("connection=%zu rawMissing timestamp=%llu\n", connection, reading->GetTimestamp());
        return false;
    }
    GameInputRawDeviceReportInfo info{};
    raw->GetReportInfo(&info);
    auto found = std::find_if(reports.begin(), reports.end(), [info](const Report& report) {
        return report.info.kind == info.kind && report.info.id == info.id && report.info.size == info.size;
    });
    if (found == reports.end() || raw->GetRawDataSize() != info.size) {
        std::printf("connection=%zu invalidDescriptor id=%u size=%u actual=%zu\n",
            connection, info.id, info.size, raw->GetRawDataSize());
        return false;
    }
    if (raw->GetRawData(found->bytes.size(), found->bytes.data()) != found->bytes.size()) {
        std::printf("connection=%zu truncated id=%u\n", connection, info.id);
        return false;
    }
    if (!found->received || found->bytes != found->previous) {
        std::printf("connection=%zu timestamp=%llu id=%u size=%u data=", connection, reading->GetTimestamp(), info.id, info.size);
        for (auto byte : found->bytes) std::printf("%02X", static_cast<unsigned>(byte));
        std::puts("");
        std::copy(found->bytes.begin(), found->bytes.end(), found->previous.begin());
    }
    found->received = true;
    return true;
}
}
int RawProbeMain(int argc, char** argv) {
    char* end{};
    const long seconds = argc == 2 ? std::strtol(argv[1], &end, 10) : 0;
    if (argc > 2 || (argc == 2 && (!end || end == argv[1] || *end || seconds < 0 || seconds > 300))) {
        std::puts("Usage: XbControllerRawProbe [seconds:0..300]"); return 1;
    }
    try {
        auto enumeration = std::make_unique<Enumeration>();
        auto hr = GameInputCreate(&enumeration->input);
        if (FAILED(hr)) { std::printf("create=0x%08X\n", static_cast<unsigned>(hr)); return 1; }
        enumeration->input->SetFocusPolicy(GameInputEnableBackgroundInput);
        GameInputCallbackToken callback{};
        hr = enumeration->input->RegisterDeviceCallback(nullptr, GameInputKindGamepad, GameInputDeviceConnected,
            GameInputBlockingEnumeration, enumeration.get(), Connected, &callback);
        // 列挙後の callback を止め、COM 参照と live status で捕捉中の接続を確認する。
        if (callback && !enumeration->input->UnregisterCallback(callback)) {
            enumeration.release(); // callback context を解放しない。プロセス終了で回収する。
            std::puts("unregisterFailed: capture aborted"); return 1;
        }
        if (FAILED(hr) || enumeration->failed) { std::puts("enumerationFailed"); return 1; }
        std::printf("connections=%zu passiveOnly=1 seconds=%ld\n", enumeration->devices.size(), seconds);
        bool captureFailed{};
        for (std::size_t index = 0; index < enumeration->devices.size(); ++index) {
            auto& device = enumeration->devices[index];
            const GameInputDeviceInfo* info{};
            hr = device->GetDeviceInfo(&info);
            if (FAILED(hr) || !info) { std::printf("connection=%zu infoFailed\n", index); captureFailed = true; continue; }
            std::printf("connection=%zu firmware=%u.%u.%u.%u inputKinds=0x%08X motors=0x%X inputReports=%u outputReports=%u\n",
                index, info->firmwareVersion.major, info->firmwareVersion.minor, info->firmwareVersion.build,
                info->firmwareVersion.revision, static_cast<unsigned>(info->supportedInput),
                static_cast<unsigned>(info->supportedRumbleMotors), info->inputReportCount, info->outputReportCount);
            std::vector<Report> reports;
            if (info->inputReportCount && !info->inputReportInfo) { std::puts("invalidInputMetadata"); captureFailed = true; continue; }
            for (std::uint32_t i = 0; i < info->inputReportCount; ++i) {
                const auto descriptor = info->inputReportInfo[i];
                std::printf(" inputDescriptor kind=%u id=%u size=%u\n", static_cast<unsigned>(descriptor.kind), descriptor.id, descriptor.size);
                if (descriptor.kind == GameInputRawInputReport && descriptor.size) {
                    Report report; report.info = descriptor;
                    report.bytes.resize(descriptor.size); report.previous.resize(descriptor.size);
                    reports.push_back(std::move(report));
                }
            }
            if (info->outputReportCount && !info->outputReportInfo) { std::puts("invalidOutputMetadata"); captureFailed = true; continue; }
            for (std::uint32_t i = 0; i < info->outputReportCount; ++i) {
                const auto descriptor = info->outputReportInfo[i];
                std::printf(" outputDescriptor kind=%u id=%u size=%u\n", static_cast<unsigned>(descriptor.kind), descriptor.id, descriptor.size);
            }
            if (!(info->supportedInput & GameInputKindRawDeviceReport) || reports.empty()) {
                std::puts("rawUnavailable: no decoder or independent paddle claim"); continue;
            }
            ComPtr<IGameInputReading> reference;
            const auto start = GetTickCount64();
            unsigned long long samples{}, gaps{};
            do {
                if (!(device->GetDeviceStatus() & GameInputDeviceConnected)) { std::puts("disconnected: rerun for new attachment"); break; }
                const auto cutoff = enumeration->input->GetCurrentTimestamp();
                for (;;) {
                    if (seconds && GetTickCount64() - start >= static_cast<ULONGLONG>(seconds) * 1000) break;
                    ComPtr<IGameInputReading> reading;
                    hr = reference ? enumeration->input->GetNextReading(reference.Get(), GameInputKindRawDeviceReport, device.Get(), &reading)
                        : enumeration->input->GetCurrentReading(GameInputKindRawDeviceReport, device.Get(), &reading);
                    if (hr == GAMEINPUT_E_READING_NOT_FOUND) break;
                    if (hr == GAMEINPUT_E_REFERENCE_READING_TOO_OLD) {
                        ++gaps; reference.Reset(); std::puts("historyGap: lost edges not inferred"); break;
                    }
                    if (FAILED(hr) || !reading) {
                        if (SUCCEEDED(hr)) hr = E_UNEXPECTED;
                        std::printf("readingError=0x%08X\n", static_cast<unsigned>(hr)); break;
                    }
                    if (reading->GetTimestamp() > cutoff) break;
                    if (reference && (reading.Get() == reference.Get() || reading->GetTimestamp() < reference->GetTimestamp())) {
                        std::puts("invalidHistory: capture aborted"); hr = E_FAIL; break;
                    }
                    if (!Receive(reading.Get(), reports, index)) { hr = E_FAIL; break; }
                    ++samples; reference = std::move(reading);
                }
                if (FAILED(hr) && hr != GAMEINPUT_E_READING_NOT_FOUND && hr != GAMEINPUT_E_REFERENCE_READING_TOO_OLD) {
                    captureFailed = true; break;
                }
                if (seconds) Sleep(10);
            } while (GetTickCount64() - start < static_cast<ULONGLONG>(seconds) * 1000);
            std::printf("connection=%zu samples=%llu gaps=%llu physicalAcceptance=unverified\n", index, samples, gaps);
        }
        return captureFailed ? 1 : 0;
    } catch (...) { std::puts("captureFailed: allocation or runtime exception"); return 1; }
}
#ifndef XB_RAW_PROBE_TEST
int main(int argc, char** argv) { return RawProbeMain(argc, argv); }
#endif
