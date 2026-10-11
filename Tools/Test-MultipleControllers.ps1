# 実 Controller と一覧管理を2台の合成状態で実行する。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$fixture = @'
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
using UnityEngine.InputSystem.Processors;
using UnityEngine.InputSystem.LowLevel;
namespace UnityEngine {
    public enum RuntimeInitializeLoadType { SubsystemRegistration }
    public sealed class RuntimeInitializeOnLoadMethodAttribute : Attribute {
        public RuntimeInitializeOnLoadMethodAttribute(RuntimeInitializeLoadType type) {}
    }
    public struct Vector2 {
        public float x, y;
        public Vector2(float x, float y) { this.x = x; this.y = y; }
        public static Vector2 zero => default;
        public Vector2 normalized {
            get { float size = (float)Math.Sqrt(x*x + y*y); return size == 0 ? zero : new Vector2(x/size, y/size); }
        }
    }
    public static class Mathf { public static float Clamp01(float value) => Math.Max(0, Math.Min(1, value)); }
    public static class Application {
        public static bool isPlaying = true, isFocused = true;
        public static event Action<bool> focusChanged { add {} remove {} }
        public static event Action quitting { add {} remove {} }
    }
}
namespace UnityEngine.InputSystem.Controls {
    public class ButtonControl { public bool isPressed, wasPressedThisFrame, wasReleasedThisFrame; }
    public class AxisControl : ButtonControl { public float ReadValue() => 0; }
    public class Vector2Control {
        public ButtonControl up, down, left, right;
        public UnityEngine.Vector2 ReadValue() => default;
    }
}
namespace UnityEngine.InputSystem.Processors {
    public class StickDeadzoneProcessor {
        public UnityEngine.Vector2 Process(UnityEngine.Vector2 value, object control) => value;
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
        public bool added = true, enabled = true;
        public int deviceId;
        public Controls.ButtonControl startButton, selectButton, aButton, bButton, xButton, yButton,
            leftShoulder, rightShoulder, leftStickButton, rightStickButton;
        public Controls.Vector2Control leftStick, rightStick, dpad;
        public Controls.AxisControl leftTrigger, rightTrigger;
        public static readonly List<Gamepad> all = new List<Gamepad>();
        public void SetMotorSpeeds(float low, float high) {}
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
    internal static class NativeApi {
        internal const uint Version = 1;
        internal const int InsufficientBuffer = unchecked((int)0x8007007A), HistoryResync = unchecked((int)0x838A0004);
        internal static NativeSnapshot[] Devices = Array.Empty<NativeSnapshot>();
        internal static readonly Dictionary<ulong, float[]> Output = new Dictionary<ulong, float[]>();
        internal static readonly List<ulong> Calls = new List<ulong>();
        internal static int Shutdowns;
        internal static int xb_initialize(uint version, uint size) => 0;
        internal static int xb_poll(NativeSnapshot[] buffer, uint capacity, out uint count, out int diagnostic) {
            count = (uint)Devices.Length; diagnostic = 0;
            if (capacity < count) return InsufficientBuffer;
            Array.Copy(Devices, buffer, Devices.Length);
            return 0;
        }
        internal static int xb_rumble(ulong token, float low, float high, float left, float right) {
            Calls.Add(token);
            foreach (var device in Devices) if (device.Token == token) {
                Output[token] = new[] { low, high, left, right };
                return 0;
            }
            return unchecked((int)0x80070490);
        }
        internal static int xb_shutdown() { Shutdowns++; return 0; }
        internal static void xb_resync() {}
    }
    public static class MultipleControllerVerification {
        private static int assertions;
        private static readonly MethodInfo poll = typeof(XboxControllers).GetMethod("PollNative", BindingFlags.NonPublic | BindingFlags.Static);
        private static void Check(bool value, string message) { assertions++; if (!value) throw new Exception(message); }
        private static bool Near(float actual, float expected) => Math.Abs(actual - expected) < 0.0001f;
        private static bool Vector(UnityEngine.Vector2 value, float x, float y) => Near(value.x, x) && Near(value.y, y);
        private static void Tick(params NativeSnapshot[] states) { NativeApi.Devices = states; poll.Invoke(null, null); }
        private static NativeSnapshot State(ulong token, XboxButton button, float axis, float trigger, uint motors) {
            return new NativeSnapshot { Token = token, Timestamp = token * 10, Supported = (ulong)(XboxButton.A | XboxButton.B),
                Buttons = (ulong)button, Pressed = (ulong)button, LeftX = axis, LeftY = -axis,
                RightX = -axis, RightY = axis, LeftTrigger = trigger, RightTrigger = 1-trigger, Rumble = motors };
        }
        private static bool Output(ulong token, float low, float high, float left, float right) {
            var value = NativeApi.Output[token];
            return Near(value[0], low) && Near(value[1], high) && Near(value[2], left) && Near(value[3], right);
        }
        private static Controller Find(ulong token) {
            foreach (var pad in XboxControllers.All) if (pad.ConnectionId == token) return pad;
            throw new Exception("接続がありません");
        }
        public static int Run() {
            var one = State(11, XboxButton.A, 0.4f, 0.25f, 15);
            var two = State(22, XboxButton.B, -0.7f, 0.8f, 3);
            NativeApi.Devices = new[] { one, two };
            XboxControllers.Initialize();
            var view = XboxControllers.All;
            var first = Find(11);
            var second = Find(22);
            Check(XboxControllers.Backend == ControllerBackend.WindowsGameInput && view.Count == 2, "native経路に2台を列挙する");
            Check(first.IsConnected && second.IsConnected && !ReferenceEquals(first, second), "異なる参照で2台を保持する");
            Check(first.IsPressed(XboxButton.A) && !first.IsPressed(XboxButton.B), "1台目のボタンを分離する");
            Check(second.IsPressed(XboxButton.B) && !second.IsPressed(XboxButton.A), "2台目のボタンを分離する");
            Check(first.WasPressed(XboxButton.A) && !second.WasPressed(XboxButton.A), "押下edgeを分離する");
            Check(Vector(first.LeftStick, 0.4f, -0.4f) && Vector(second.LeftStick, -0.7f, 0.7f), "左スティックを分離する");
            Check(Vector(first.RightStick, -0.4f, 0.4f) && Vector(second.RightStick, 0.7f, -0.7f), "右スティックを分離する");
            Check(Near(first.LeftTrigger, 0.25f) && Near(second.LeftTrigger, 0.8f), "左トリガーを分離する");
            Check(Near(first.RightTrigger, 0.75f) && Near(second.RightTrigger, 0.2f), "右トリガーを分離する");
            Check(first.SupportedRumbleMotors == 15 && second.SupportedRumbleMotors == 3, "装置別の対応情報を保持する");
            Check(first.SetRumble(0.25f, 0.5f, 0.1f, 0.2f) && Output(11, 0.25f, 0.5f, 0.1f, 0.2f), "1台目へ4モーターを要求する");
            Check(!NativeApi.Output.ContainsKey(22), "1台目の振動で2台目を変更しない");
            Check(second.SetRumble(0.7f, 0.15f) && Output(22, 0.7f, 0.15f, 0, 0), "2台目へ本体振動を要求する");
            Check(Output(11, 0.25f, 0.5f, 0.1f, 0.2f), "2台目の振動で1台目を変更しない");
            int calls = NativeApi.Calls.Count;
            Check(!second.SetRumble(0, 0, 0.5f, 0) && NativeApi.Calls.Count == calls && Output(22, 0.7f, 0.15f, 0, 0), "非対応要求で他の出力を変更しない");
            one = State(11, XboxButton.B, 0.9f, 0.1f, 15);
            one.Released = (ulong)XboxButton.A;
            two = State(22, XboxButton.A, -0.2f, 0.6f, 3);
            Tick(one, two);
            Check(ReferenceEquals(first, Find(11)) && ReferenceEquals(second, Find(22)), "更新で接続中の参照を保持する");
            Check(first.WasReleased(XboxButton.A) && !second.WasReleased(XboxButton.A), "解放edgeを分離する");
            Check(first.IsPressed(XboxButton.B) && second.IsPressed(XboxButton.A), "異なる次の入力を分離する");
            two.LeftX = -0.8f;
            Tick(two);
            Check(view.Count == 1 && ReferenceEquals(second, Find(22)) && Near(second.LeftStick.x, -0.8f), "一方の切断後も他方の更新と参照を保持する");
            Check(Output(22, 0.7f, 0.15f, 0, 0) && NativeApi.Calls[NativeApi.Calls.Count-1] == 11, "切断した装置だけへ停止を要求する");
            Check(!first.IsConnected && !first.IsPressed(XboxButton.A) && !first.IsPressed(XboxButton.B), "古い参照のボタンを中立化する");
            Check(!first.WasPressed(XboxButton.B) && !first.WasReleased(XboxButton.A), "古い参照のedgeを中立化する");
            Check(Vector(first.LeftStick, 0, 0) && Vector(first.RightStick, 0, 0) && Vector(first.Dpad, 0, 0), "古い参照の方向を中立化する");
            Check(first.LeftTrigger == 0 && first.RightTrigger == 0 && first.TimestampMicroseconds == 0, "古い参照の軸と時刻を中立化する");
            calls = NativeApi.Calls.Count;
            Check(!first.SetRumble(1, 1) && NativeApi.Calls.Count == calls, "古い参照から他の装置を振動させない");
            Tick(two, State(33, XboxButton.B, 0.5f, 0.3f, 15));
            var reconnected = Find(33);
            Check(view.Count == 2 && !ReferenceEquals(first, reconnected) && reconnected.ConnectionId != first.ConnectionId, "再接続で新しいtokenと参照を使う");
            Check(ReferenceEquals(second, Find(22)) && second.IsPressed(XboxButton.A) && reconnected.IsPressed(XboxButton.B), "再接続後も2台の入力を分離する");
            Check(!first.IsConnected && Vector(first.LeftStick, 0, 0), "再接続後も古い参照は中立値を返す");
            Check(reconnected.SetRumble(0.2f, 0.3f, 0.4f, 0.5f) && Output(33, 0.2f, 0.3f, 0.4f, 0.5f) && Output(22, 0.7f, 0.15f, 0, 0), "新しい接続の振動を他方と分離する");
            XboxControllers.Shutdown();
            Check(view.Count == 0 && NativeApi.Shutdowns == 1, "終了で一覧とbackendを閉じる");
            Check(!second.IsConnected && !reconnected.IsConnected && Output(22, 0, 0, 0, 0) && Output(33, 0, 0, 0, 0), "終了で両方の所有出力と参照を停止する");
            return assertions;
        }
    }
}
'@
$sources = foreach ($path in @('Runtime/Controller.cs', 'Runtime/XboxControllers.cs', 'Runtime/XboxButton.cs')) {
    $source = Get-Content -LiteralPath (Join-Path $repository $path) -Raw -Encoding utf8
    [regex]::Replace($source, '(?m)^using [^\r\n]+;\r?\n', '')
}
$native = Get-Content -LiteralPath (Join-Path $repository 'Runtime/NativeApi.cs') -Raw -Encoding utf8
$snapshot = $native.Substring(0, $native.IndexOf('    internal static class NativeApi')) + "}`n"
$snapshot = $snapshot.Replace('using System.Runtime.InteropServices;', '')
Add-Type -TypeDefinition ("using System.Runtime.InteropServices;`n" + $fixture + "`n" + ($sources -join "`n") + "`n" + $snapshot) -CompilerOptions '-define:UNITY_STANDALONE_WIN'
'PASS assertions=' + [XbController.MultipleControllerVerification]::Run()
'合成試験のみ。Unity・GameInput・デッドゾーンは代役です。実機応答は未検証です。'
