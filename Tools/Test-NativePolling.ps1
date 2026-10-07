# 実 facade を合成 NativeApi と最小 Unity 型でコンパイルする。実機・Unity 検証とは別。
[CmdletBinding()]
param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Runtime/XboxControllers.cs'))
$ErrorActionPreference = 'Stop'
$fixture = @'
using System;
using System.Collections.Generic;
using System.Reflection;
namespace UnityEngine {
    public enum RuntimeInitializeLoadType { SubsystemRegistration }
    public sealed class RuntimeInitializeOnLoadMethodAttribute : Attribute {
        public RuntimeInitializeOnLoadMethodAttribute(RuntimeInitializeLoadType type) {}
    }
    public static class Application {
        public static bool isPlaying, isFocused = true;
        public static event Action<bool> focusChanged { add {} remove {} }
        public static event Action quitting { add {} remove {} }
    }
}
namespace UnityEngine.InputSystem.LowLevel {
    public enum InputUpdateType { Manual, Fixed, Dynamic, Editor }
    public static class InputState { public static InputUpdateType currentUpdateType; }
}
namespace UnityEngine.InputSystem {
    public class InputDevice {}
    public enum InputDeviceChange { Added }
    public class Gamepad : InputDevice {
        public bool enabled = true;
        public static readonly List<Gamepad> all = new List<Gamepad>();
    }
    public class InputSettings {
        public enum UpdateMode { ProcessEventsManually, ProcessEventsInFixedUpdate, ProcessEventsInDynamicUpdate }
        public UpdateMode updateMode;
    }
    public static class InputSystem {
        public static readonly InputSettings settings = new InputSettings();
        public static event Action onBeforeUpdate { add {} remove {} }
        public static event Action<InputDevice, InputDeviceChange> onDeviceChange { add {} remove {} }
    }
}
namespace XbController {
    public enum ControllerBackend { WindowsGameInput, UnityInputSystem }
    internal struct NativeSnapshot { public ulong Token; }
    public sealed class Controller {
        public ulong ConnectionId { get; private set; }
        public UnityEngine.InputSystem.Gamepad UnityDevice { get; private set; }
        public bool IsConnected = true;
        public int Updates, Invalidations;
        internal Controller(NativeSnapshot state) { ConnectionId = state.Token; }
        internal Controller(UnityEngine.InputSystem.Gamepad pad) { UnityDevice = pad; }
        internal void Update(NativeSnapshot state) { Updates++; }
        internal void Invalidate() { Invalidations++; IsConnected = false; }
        internal void StopRumble() {}
        internal void Neutralize() {}
    }
    internal static class NativeApi {
        internal const int InsufficientBuffer = unchecked((int)0x8007007A);
        internal sealed class Reply {
            internal uint Count;
            internal int Result, Diagnostic;
            internal ulong[] Tokens;
        }
        internal static readonly Queue<Reply> Replies = new Queue<Reply>();
        internal static readonly List<uint> Capacities = new List<uint>();
        internal static NativeSnapshot[] LastBuffer;
        internal static void Queue(int result, uint count, int diagnostic = 0, params ulong[] tokens) {
            Replies.Enqueue(new Reply { Result = result, Count = count, Diagnostic = diagnostic, Tokens = tokens });
        }
        internal static int xb_poll(NativeSnapshot[] buffer, uint capacity, out uint count, out int diagnostic) {
            Capacities.Add(capacity); LastBuffer = buffer;
            var reply = Replies.Dequeue(); count = reply.Count; diagnostic = reply.Diagnostic;
            if (reply.Result == InsufficientBuffer && count <= capacity) throw new Exception("不正な合成容量要求");
            if (reply.Result >= 0) {
                if (count > capacity || count != reply.Tokens.Length) throw new Exception("不正な合成 snapshot");
                for (int i = 0; i < count; i++) buffer[i].Token = reply.Tokens[i];
            }
            return reply.Result;
        }
        internal static int xb_shutdown() { return 0; }
        internal static void xb_resync() {}
    }
    public static class NativePollingVerification {
        private static int assertions;
        private static void Check(bool value, string message) {
            assertions++; if (!value) throw new Exception(message);
        }
        public static int Run() {
            var type = typeof(XboxControllers);
            var poll = type.GetMethod("PollNative", BindingFlags.NonPublic | BindingFlags.Static);
            var controllers = (List<Controller>)type.GetField("controllers", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
            NativeApi.Queue(NativeApi.InsufficientBuffer, 1);
            NativeApi.Queue(0, 1, 123, 11);
            poll.Invoke(null, null);
            var retained = controllers[0];
            NativeApi.Capacities.Clear();
            NativeApi.Queue(NativeApi.InsufficientBuffer, 2);
            NativeApi.Queue(NativeApi.InsufficientBuffer, 3);
            NativeApi.Queue(0, 3, 123, 11, 22, 33);
            poll.Invoke(null, null);
            Check(NativeApi.Capacities.Count == 3 && NativeApi.Capacities[1] == 2 && NativeApi.Capacities[2] == 3, "連続する容量拡張");
            Check(controllers.Count == 3 && ReferenceEquals(retained, controllers[0]) && retained.Updates == 1, "成功時の既存参照と新規接続");
            NativeApi.Capacities.Clear();
            for (uint count = 4; count <= 8; count++) NativeApi.Queue(NativeApi.InsufficientBuffer, count, -1);
            poll.Invoke(null, null);
            Check(NativeApi.Capacities.Count == 5 && NativeApi.Replies.Count == 0, "初回と最大4回の再試行");
            Check(controllers.Count == 3 && ReferenceEquals(retained, controllers[0]) && retained.IsConnected && retained.Invalidations == 0, "再試行上限でも参照を保持");
            Check(XboxControllers.BackendError == 123 && retained.Updates == 1, "容量不足は診断とキャッシュを変更しない");
            var removed = controllers[1];
            NativeApi.Queue(0, 1, 456, 11);
            poll.Invoke(null, null);
            Check(ReferenceEquals(retained, controllers[0]) && retained.Updates == 2 && XboxControllers.BackendError == 456, "次回成功で同じ参照を更新");
            Check(controllers.Count == 1 && removed.Invalidations == 1, "成功した列挙だけで切断を反映");
            var buffer = NativeApi.LastBuffer;
            NativeApi.Queue(0, 1, 0, 11);
            poll.Invoke(null, null);
            Check(ReferenceEquals(buffer, NativeApi.LastBuffer), "通常更新の配列再利用");
            NativeApi.Queue(unchecked((int)0x80004005), 0);
            poll.Invoke(null, null);
            Check(controllers.Count == 0 && retained.Invalidations == 1 && XboxControllers.BackendError == unchecked((int)0x80004005), "致命的な取得失敗は無効化");
            Check(NativeApi.Replies.Count == 0, "全合成応答を消費");
            return assertions;
        }
    }
}
'@
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding utf8
Add-Type -TypeDefinition ("using System.Reflection;`n" + $source + "`n" + $fixture.Replace('using System;', '').Replace('using System.Collections.Generic;', '').Replace('using System.Reflection;', ''))
'PASS assertions=' + [XbController.NativePollingVerification]::Run()
