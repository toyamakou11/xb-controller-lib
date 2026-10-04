#include "gatt_paddles.h"
#include <robuffer.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Storage.Streams.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <memory>
#include <mutex>
#include <string_view>
#include <thread>
#include <vector>

namespace xb_gatt {
namespace {
using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Devices::Enumeration;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using Cccd = GattClientCharacteristicConfigurationDescriptorValue;
// 公開 API 上の vendor protocol。機種名・VID/PID・接続順で装置を選ばない。
// https://github.com/hifihedgehog/SDL/blob/feat/hidmaestro-filter/src/joystick/windows/SDL_xinput_paddle_gatt.cpp
// 17-byte payload の byte14 の bits0-3 は物理 P1-P4。profile による補完はしない。
constexpr guid ServiceUuid{0x00000001,0x5f60,0x4c4f,{0x9c,0x83,0xa7,0x95,0x32,0x98,0xd4,0x0d}};
constexpr guid CharacteristicUuid{0x00000005,0x5f60,0x4c4f,{0x9c,0x83,0xa7,0x95,0x32,0x98,0xd4,0x0d}};
struct Attachment {
    std::uint64_t token;
    guid container;
    std::atomic<bool> active{true}, retire{}, detached{}, streaming{}, ambiguous{};
    std::atomic<std::uint64_t> generation{};
    std::mutex mutex;
    Sample sample{};
    // 以下は MTA worker だけが操作する。
    bool started{}, subscribed{}, attempted{}, cleaned{}, cleanupBlocked{};
    ULONGLONG retryAt{};
    unsigned retryDelay{1000};
    ULONGLONG cleanupWaitSince{};
    ULONGLONG cleanupRetryAt{};
    unsigned cleanupDelay{1000};
    Cccd original{Cccd::None};
    event_token event{};
    BluetoothLEDevice device{nullptr};
    GattDeviceService service{nullptr};
    GattCharacteristic characteristic{nullptr};
    Attachment(std::uint64_t value, GUID id) : token(value), container(id) {}
};
struct Context {
    std::mutex mutex;
    std::condition_variable wake, finishedEvent;
    std::vector<std::shared_ptr<Attachment>> attachments;
    std::atomic<bool> stopping{};
    bool finished{};
    HRESULT result{S_OK};
    HRESULT attachError{S_OK};
    std::thread worker;
};
std::mutex ownerMutex;
// 終了失敗時に DLL の実行資源を破棄しない。成功した Shutdown だけが delete する。
Context* context{};

void Neutral(Attachment& item, HRESULT error) noexcept {
    std::lock_guard<std::mutex> lock(item.mutex);
    item.sample = {};
    item.sample.error = error;
}

template<class T> T Await(Context& c, Attachment& item, IAsyncOperation<T> const& operation, bool cleanup = false) {
    const auto deadline = GetTickCount64() + 10000;
    bool canceled{};
    for (;;) {
        const auto status = operation.Status();
        if (status != AsyncStatus::Started) {
            if (canceled) throw hresult_error(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
            return operation.GetResults();
        }
        if (!canceled && (GetTickCount64() >= deadline || (!cleanup && (c.stopping || item.retire)))) {
            canceled = true;
            Neutral(item,HRESULT_FROM_WIN32(ERROR_TIMEOUT));
            // Cancel の失敗でも、開始済みの書き込みを残して cleanup に進まない。
            try { operation.Cancel(); } catch (...) { }
        }
        // Cancel は rollback ではない。terminal になるまで operation と所有資源を保持する。
        Sleep(10);
    }
}

std::uint64_t Address(std::wstring_view text) {
    if (text.size() != 12 && text.size() != 17) throw hresult_error(E_INVALIDARG);
    std::uint64_t value{};
    for (std::size_t i = 0; i < text.size(); ++i) {
        const auto ch = text[i];
        if (text.size() == 17 && i % 3 == 2) {
            if (ch != L':' && ch != L'-') throw hresult_error(E_INVALIDARG);
            continue;
        }
        const unsigned digit = ch >= L'0' && ch <= L'9' ? ch - L'0' :
            ch >= L'a' && ch <= L'f' ? ch - L'a' + 10 : ch >= L'A' && ch <= L'F' ? ch - L'A' + 10 : 16;
        if (digit > 15) throw hresult_error(E_INVALIDARG);
        value = (value << 4) | digit;
    }
    if (!value) throw hresult_error(E_INVALIDARG);
    return value;
}

guid Container(DeviceInformation const& info) {
    const auto properties = info.Properties();
    constexpr wchar_t key[] = L"System.Devices.Aep.ContainerId";
    if (!properties.HasKey(key)) return {};
    auto property = properties.Lookup(key).try_as<IPropertyValue>();
    return property && property.Type() == PropertyType::Guid ? property.GetGuid() : guid{};
}

void Accumulate(Attachment& item, std::uint8_t const* bytes, std::size_t size, std::uint64_t generation = 0) noexcept {
    std::lock_guard<std::mutex> lock(item.mutex);
    if (!item.active || !item.streaming || (generation && generation != item.generation)) return;
    if (size != 17 || !bytes) {
        item.sample = {};
        item.sample.error = HRESULT_FROM_WIN32(ERROR_INVALID_DATA);
        return;
    }
    const auto buttons = static_cast<std::uint8_t>(bytes[14] & 0x0f);
    auto& value = item.sample;
    if (value.received) {
        value.pressed |= static_cast<std::uint8_t>(buttons & ~value.buttons);
        value.released |= static_cast<std::uint8_t>(value.buttons & ~buttons);
    }
    // 初回・gap後は最新値に同期し、欠落した押下/解放を作らない。
    value.buttons = buttons;
    value.received = true;
    value.error = S_OK;
}

void Receive(std::shared_ptr<Attachment> const& item, std::uint64_t generation, GattValueChangedEventArgs const& args) noexcept {
    if (!item->active.load() || !item->streaming.load() || generation != item->generation) return;
    try {
        const auto buffer = args.CharacteristicValue();
        if (buffer.Length() != 17) { Accumulate(*item,nullptr,0,generation); return; }
        auto access = buffer.as<::Windows::Storage::Streams::IBufferByteAccess>();
        std::uint8_t* bytes{};
        check_hresult(access->Buffer(&bytes));
        if (!bytes) throw hresult_error(E_POINTER);
        std::array<std::uint8_t,17> payload{};
        std::memcpy(payload.data(), bytes, payload.size());
        Accumulate(*item,payload.data(),payload.size(),generation);
    } catch (...) { Accumulate(*item,nullptr,0,generation); }
}

void Discover(Context& c, std::shared_ptr<Attachment> const& item) {
    item->started = true;
    auto endpoints = Await(c,*item,DeviceInformation::FindAllAsync(
        BluetoothLEDevice::GetDeviceSelectorFromPairingState(true),
        {L"System.Devices.Aep.ContainerId",L"System.Devices.Aep.DeviceAddress"},DeviceInformationKind::AssociationEndpoint));
    DeviceInformation selected{nullptr};
    for (auto const& endpoint : endpoints) {
        if (Container(endpoint) != item->container) continue;
        if (selected) throw hresult_error(HRESULT_FROM_WIN32(ERROR_DUP_NAME));
        selected = endpoint;
    }
    // USB 等に対応する LE endpoint がないことは、通常の fallback 条件。
    if (!selected) { Neutral(*item,S_OK); item->active = false; item->retire = true; return; }
    auto properties = selected.Properties();
    constexpr wchar_t addressKey[] = L"System.Devices.Aep.DeviceAddress";
    if (!properties.HasKey(addressKey)) throw hresult_error(E_INVALIDARG);
    auto addressProperty = properties.Lookup(addressKey).try_as<IPropertyValue>();
    if (!addressProperty || addressProperty.Type() != PropertyType::String) throw hresult_error(E_INVALIDARG);
    const auto addressText = addressProperty.GetString();
    const auto address = Address(std::wstring_view(addressText));
    // 実機で確認した公開 address API。FromIdAsync の UI consent 経路を使わない。
    item->device = Await(c,*item,BluetoothLEDevice::FromBluetoothAddressAsync(address));
    if (!item->device || item->device.BluetoothAddress() != address || item->device.DeviceInformation().Id() != selected.Id())
        throw hresult_error(E_INVALIDARG);
    auto services = Await(c,*item,item->device.GetGattServicesForUuidAsync(ServiceUuid,BluetoothCacheMode::Cached));
    if (services.Status() == GattCommunicationStatus::Success && services.Services().Size() == 0)
        services = Await(c,*item,item->device.GetGattServicesForUuidAsync(ServiceUuid,BluetoothCacheMode::Uncached));
    if (services.Status() != GattCommunicationStatus::Success || services.Services().Size() != 1)
        throw hresult_error(HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED));
    item->service = services.Services().GetAt(0);
    if (item->service.Uuid() != ServiceUuid) throw hresult_error(E_INVALIDARG);
    auto characteristics = Await(c,*item,item->service.GetCharacteristicsForUuidAsync(CharacteristicUuid,BluetoothCacheMode::Cached));
    if (characteristics.Status() == GattCommunicationStatus::Success && characteristics.Characteristics().Size() == 0)
        characteristics = Await(c,*item,item->service.GetCharacteristicsForUuidAsync(CharacteristicUuid,BluetoothCacheMode::Uncached));
    if (characteristics.Status() != GattCommunicationStatus::Success || characteristics.Characteristics().Size() != 1)
        throw hresult_error(HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED));
    item->characteristic = characteristics.Characteristics().GetAt(0);
    if (item->characteristic.Uuid() != CharacteristicUuid) throw hresult_error(E_INVALIDARG);
    if ((item->characteristic.CharacteristicProperties() & GattCharacteristicProperties::Notify) == GattCharacteristicProperties::None)
        throw hresult_error(HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED));
    auto config = Await(c,*item,item->characteristic.ReadClientCharacteristicConfigurationDescriptorAsync());
    if (config.Status() != GattCommunicationStatus::Success) throw hresult_error(E_FAIL);
    item->original = config.ClientCharacteristicConfigurationDescriptor();
    if (item->original != Cccd::None && item->original != Cccd::Notify) throw hresult_error(E_NOTIMPL);
    const auto generation = ++item->generation;
    item->event = item->characteristic.ValueChanged([item,generation](GattCharacteristic const&,GattValueChangedEventArgs const& args) noexcept { Receive(item,generation,args); });
    item->subscribed = true;
    if (c.stopping || item->retire || !item->active) throw hresult_error(HRESULT_FROM_WIN32(ERROR_CANCELLED));
    // Notify の再登録は必要だが、既存 Notify を None に切り替えない。
    item->attempted = true;
    const auto status = Await(c,*item,item->characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(Cccd::Notify));
    if (status != GattCommunicationStatus::Success) throw hresult_error(E_FAIL);
    item->streaming = true;
}

bool Cleanup(Context& c, Attachment& item) noexcept {
    try {
        if (item.subscribed) {
            item.characteristic.ValueChanged(item.event);
            item.subscribed = false;
        }
        if (item.attempted && item.original == Cccd::None) {
            auto config = Await(c,item,item.characteristic.ReadClientCharacteristicConfigurationDescriptorAsync(),true);
            if (config.Status() != GattCommunicationStatus::Success) throw hresult_error(E_FAIL);
            // CCCD に compare/exchange はない。競合する他 client の完全な保護は保証しない。
            if (config.ClientCharacteristicConfigurationDescriptor() == Cccd::Notify &&
                Await(c,item,item.characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(item.original),true) != GattCommunicationStatus::Success)
                throw hresult_error(E_FAIL);
        }
        item.attempted = false;
        item.characteristic = nullptr;
        if (item.service) { item.service.Close(); item.service = nullptr; }
        if (item.device) { item.device.Close(); item.device = nullptr; }
        item.cleaned = true;
        return true;
    } catch (hresult_error const& error) { Neutral(item,error.code()); }
    catch (...) { Neutral(item,E_FAIL); }
    item.cleanupBlocked = true;
    item.cleanupRetryAt = GetTickCount64() + item.cleanupDelay;
    item.cleanupDelay = (std::min)(item.cleanupDelay * 2,8000u);
    return false;
}

bool Transient(HRESULT error) noexcept {
    return error == E_FAIL || error == HRESULT_FROM_WIN32(ERROR_TIMEOUT) ||
        error == HRESULT_FROM_WIN32(ERROR_BUSY) || error == HRESULT_FROM_WIN32(ERROR_DEVICE_NOT_CONNECTED);
}

bool RetryReady(Attachment const& item, bool stopping, ULONGLONG now) noexcept {
    return !stopping && !item.detached && !item.ambiguous && item.retire && item.cleaned && item.retryAt && now >= item.retryAt;
}

bool Connected(Attachment const& item) noexcept {
    try { return item.device && item.device.ConnectionStatus() == BluetoothConnectionStatus::Connected; }
    catch (...) { return false; }
}

void ScheduleRetry(Attachment& item) noexcept {
    item.retryAt = GetTickCount64() + item.retryDelay;
    item.retryDelay = (std::min)(item.retryDelay * 2,8000u);
}

bool ContainerConflict(Attachment const& item, guid container) noexcept {
    return !item.detached && item.container == container;
}

bool BlocksDiscovery(Attachment const& previous, Attachment const& next) noexcept {
    // detached でも、旧 CCCD 復元が完了するまで新 subscriber を開始しない。
    return previous.token != next.token && previous.container == next.container && !previous.cleaned;
}

// c.mutex を保持して呼ぶ。単一 worker なので許可後に旧 cleanup が再開することはない。
bool CanDiscover(Context const& c, Attachment const& item) noexcept {
    for (auto const& previous : c.attachments) if (BlocksDiscovery(*previous,item)) return false;
    return true;
}

void Run(Context& c) noexcept {
    HRESULT result = S_OK;
    try {
        init_apartment(apartment_type::multi_threaded);
        for (;;) {
            std::size_t index{};
            for (;;) {
                std::shared_ptr<Attachment> item;
                { std::lock_guard<std::mutex> lock(c.mutex);
                  if (index == c.attachments.size()) break;
                  item = c.attachments[index++]; }
                if (c.stopping) { item->active = false; item->retire = true; }
                {
                    // Detach/重複 Attach と同じ lock 下で条件を再確認し、失効を上書きしない。
                    std::lock_guard<std::mutex> lock(c.mutex);
                    if (RetryReady(*item,c.stopping,GetTickCount64())) {
                        ++item->generation;
                        item->retryAt = 0; item->started = false; item->cleaned = false; item->cleanupBlocked = false;
                        item->streaming = false; item->retire = false; item->active = true;
                    }
                }
                bool discover{};
                {
                    std::lock_guard<std::mutex> lock(c.mutex);
                    if (!c.stopping && !item->retire && !item->started) {
                        if (CanDiscover(c,*item)) {
                            item->cleanupWaitSince = 0;
                            item->started = true;
                            Neutral(*item,S_OK);
                            discover = true;
                        } else {
                            const auto now = GetTickCount64();
                            if (!item->cleanupWaitSince) item->cleanupWaitSince = now;
                            // 待機は foreground を止めず、10秒後は timeout を診断して待機を継続する。
                            Neutral(*item,now - item->cleanupWaitSince >= 10000 ? HRESULT_FROM_WIN32(ERROR_TIMEOUT) : E_PENDING);
                        }
                    }
                }
                if (discover) {
                    try { Discover(c,item); }
                    catch (hresult_error const& error) {
                        Neutral(*item,error.code()); item->retire = true; item->active = false;
                        if (Transient(error.code())) {
                            ScheduleRetry(*item);
                        }
                    }
                    catch (...) { Neutral(*item,E_FAIL); item->retire = true; item->active = false; }
                }
                if (!item->retire && item->device && !Connected(*item)) {
                    Neutral(*item,HRESULT_FROM_WIN32(ERROR_DEVICE_NOT_CONNECTED));
                    item->active = false; item->retire = true;
                    ScheduleRetry(*item);
                }
                // Offline CCCD の復元失敗も、接続復帰後に 1-8秒 backoff で再試行する。
                const bool cleanupRetry = item->cleanupBlocked && GetTickCount64() >= item->cleanupRetryAt &&
                    (!item->attempted || Connected(*item));
                if (item->retire && !item->cleaned && (!item->cleanupBlocked || c.stopping || cleanupRetry))
                    (void)Cleanup(c,*item);
            }
            {
                std::lock_guard<std::mutex> lock(c.mutex);
                c.attachments.erase(std::remove_if(c.attachments.begin(),c.attachments.end(),
                    [](auto const& item) { return item->detached && item->cleaned; }),c.attachments.end());
            }
            if (c.stopping) break;
            std::unique_lock<std::mutex> lock(c.mutex);
            c.wake.wait_for(lock,std::chrono::milliseconds(50));
        }
        {
            std::lock_guard<std::mutex> lock(c.mutex);
            for (auto const& item : c.attachments) if (!item->cleaned) result = E_FAIL;
        }
        uninit_apartment();
    } catch (hresult_error const& error) { result = error.code(); }
    catch (...) { result = E_FAIL; }
    if (FAILED(result)) {
        std::lock_guard<std::mutex> lock(c.mutex);
        for (auto const& item : c.attachments) { item->active = false; item->retire = true; Neutral(*item,result); }
    }
    { std::lock_guard<std::mutex> lock(c.mutex); c.result = result; c.finished = true; }
    c.finishedEvent.notify_all();
}
}

HRESULT Initialize() noexcept {
    auto previous = Shutdown();
    if (FAILED(previous)) return previous;
    try {
        std::lock_guard<std::mutex> owner(ownerMutex);
        auto next = std::make_unique<Context>();
        next->worker = std::thread(Run,std::ref(*next));
        context = next.release();
        return S_OK;
    } catch (...) { return E_OUTOFMEMORY; }
}

void Attach(std::uint64_t token, GUID container) noexcept {
    if (!token || IsEqualGUID(container,GUID{})) return;
    try {
        std::lock_guard<std::mutex> owner(ownerMutex);
        if (!context || context->stopping) return;
        std::lock_guard<std::mutex> lock(context->mutex);
        for (auto const& item : context->attachments) if (item->token == token) return;
        auto next = std::make_shared<Attachment>(token,container);
        for (auto const& item : context->attachments) {
            if (!ContainerConflict(*item,guid(container))) continue;
            item->active = false; item->retire = true; item->ambiguous = true;
            Neutral(*item,HRESULT_FROM_WIN32(ERROR_DUP_NAME));
            next->active = false; next->retire = true; next->ambiguous = true;
            Neutral(*next,HRESULT_FROM_WIN32(ERROR_DUP_NAME));
        }
        context->attachments.push_back(std::move(next));
        context->wake.notify_one();
    } catch (...) {
        // 接続時の確保失敗を診断として残し、callback から例外を出さない。
        std::lock_guard<std::mutex> owner(ownerMutex);
        if (context) { std::lock_guard<std::mutex> lock(context->mutex); context->attachError = E_OUTOFMEMORY; }
    }
}

void Detach(std::uint64_t token) noexcept {
    std::lock_guard<std::mutex> owner(ownerMutex);
    if (!context) return;
    std::lock_guard<std::mutex> lock(context->mutex);
    for (auto const& item : context->attachments) if (item->token == token) {
        item->active = false; item->retire = true; item->detached = true;
        Neutral(*item,HRESULT_FROM_WIN32(ERROR_DEVICE_NOT_CONNECTED));
    }
    context->wake.notify_one();
}

Sample Poll(std::uint64_t token) noexcept {
    std::lock_guard<std::mutex> owner(ownerMutex);
    if (!context) return {};
    std::lock_guard<std::mutex> lock(context->mutex);
    for (auto const& item : context->attachments) if (item->token == token) {
        std::lock_guard<std::mutex> state(item->mutex);
        auto result = item->sample;
        item->sample.pressed = item->sample.released = 0;
        return result;
    }
    Sample missing{};
    missing.error = context->attachError;
    return missing;
}

void Resync() noexcept {
    std::lock_guard<std::mutex> owner(ownerMutex);
    if (!context) return;
    std::lock_guard<std::mutex> lock(context->mutex);
    for (auto const& item : context->attachments) {
        std::lock_guard<std::mutex> state(item->mutex);
        item->sample.pressed = item->sample.released = 0;
    }
}

HRESULT Shutdown() noexcept {
    Context* current{};
    {
        std::lock_guard<std::mutex> owner(ownerMutex);
        current = context;
        if (!current) return S_OK;
        current->stopping = true;
        std::lock_guard<std::mutex> lock(current->mutex);
        // 前回 terminal で終わった復元失敗は、新しい MTA worker で再試行する。
        if (current->finished) {
            if (current->worker.joinable()) current->worker.join();
            current->finished = false;
            try { current->worker = std::thread(Run,std::ref(*current)); }
            catch (...) { current->finished = true; return E_OUTOFMEMORY; }
        }
        for (auto const& item : current->attachments) { item->active = false; item->retire = true; }
        current->wake.notify_one();
    }
    std::unique_lock<std::mutex> lock(current->mutex);
    if (!current->finishedEvent.wait_for(lock,std::chrono::seconds(10),[current] { return current->finished; })) return E_FAIL;
    const auto result = current->result;
    lock.unlock();
    if (current->worker.joinable()) current->worker.join();
    if (FAILED(result)) return result;
    std::lock_guard<std::mutex> owner(ownerMutex);
    context = nullptr;
    delete current;
    return S_OK;
}
#ifdef XB_GATT_TEST
bool TestAccumulator() noexcept {
    Attachment item(1,GUID{});
    item.streaming = true;
    std::array<std::uint8_t,17> packet{};
    Accumulate(item,packet.data(),packet.size());
    if (!item.sample.received || item.sample.buttons || item.sample.pressed || item.sample.released) return false;
    for (auto mask : {1,0,2,0,15,0,1,0}) {
        packet[14] = static_cast<std::uint8_t>(mask);
        Accumulate(item,packet.data(),packet.size());
    }
    if (item.sample.buttons || item.sample.pressed != 15 || item.sample.released != 15) return false;
    Accumulate(item,packet.data(),16);
    if (item.sample.received || item.sample.buttons || item.sample.pressed || item.sample.released || SUCCEEDED(item.sample.error)) return false;
    packet[14] = 8;
    Accumulate(item,packet.data(),packet.size());
    if (!item.sample.received || item.sample.buttons != 8 || item.sample.pressed || item.sample.released) return false;
    item.active = false;
    packet[14] = 0;
    Accumulate(item,packet.data(),packet.size());
    if (item.sample.buttons != 8 || item.sample.released) return false;
    item.active = true; item.generation = 2;
    Accumulate(item,packet.data(),packet.size(),1);
    if (item.sample.buttons != 8 || item.sample.released) return false;
    // 接続復帰の候補でも、detach/曖昧 identity/停止は再有効化を禁止する。
    item.cleaned = true; item.retire = true; item.retryAt = 100;
    if (RetryReady(item,false,99) || !RetryReady(item,false,100)) return false;
    item.detached = true;
    if (RetryReady(item,false,100)) return false;
    item.detached = false; item.ambiguous = true; item.active = false; item.retire = true;
    if (RetryReady(item,false,100)) return false;
    if (!ContainerConflict(item,item.container)) return false;
    item.detached = true;
    if (ContainerConflict(item,item.container)) return false;
    item.detached = false;
    item.ambiguous = false;
    if (RetryReady(item,true,100)) return false;
    ScheduleRetry(item);
    if (!item.retryAt || item.retryDelay != 2000) return false;
    Attachment next(2,GUID{});
    item.detached = true; item.cleaned = false; item.active = false;
    if (!BlocksDiscovery(item,next)) return false;
    item.cleaned = true;
    if (BlocksDiscovery(item,next)) return false;
    // 異なる container と同一 token は、この待機条件の対象外。
    item.cleaned = false;
    next.container.Data1 = 1;
    if (BlocksDiscovery(item,next)) return false;
    next.container = item.container; next.token = item.token;
    if (BlocksDiscovery(item,next)) return false;
    try {
        Context waiting;
        auto old = std::make_shared<Attachment>(1,GUID{});
        auto replacement = std::make_shared<Attachment>(2,GUID{});
        waiting.attachments = {old,replacement};
        old->detached = true; old->active = false; old->cleanupBlocked = true;
        if (CanDiscover(waiting,*replacement)) return false;
        old->cleaned = true;
        return CanDiscover(waiting,*replacement);
    } catch (...) { return false; }
}
#endif
}
