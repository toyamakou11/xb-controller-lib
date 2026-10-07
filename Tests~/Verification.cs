using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using UnityEditor;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using XbController.Editor;
using Debug = UnityEngine.Debug;

namespace XbController.Verification
{
    public sealed class RecordingGamepad : Gamepad
    {
        public int MotorCalls;
        public float Low, High;
        public override void SetMotorSpeeds(float lowFrequency, float highFrequency)
        {
            MotorCalls++; Low = lowFrequency; High = highFrequency;
        }
    }

    [InitializeOnLoad]
    public static class Verification
    {
        private static int assertions;
        private const string Pending = "XbControllerVerificationPending";
        static Verification()
        {
            if (SessionState.GetBool(Pending, false)) EditorApplication.update += AwaitPlay;
        }
        public static void Start()
        {
            SessionState.SetBool(Pending, true);
            EditorApplication.update -= AwaitPlay;
            EditorApplication.update += AwaitPlay;
            EditorApplication.EnterPlaymode();
        }
        private static void AwaitPlay()
        {
            if (!EditorApplication.isPlaying) return;
            SessionState.EraseBool(Pending);
            EditorApplication.update -= AwaitPlay;
            XbController.TestDriver.VerificationDriver.RunTest = Run;
            new GameObject("入力検証").AddComponent<XbController.TestDriver.VerificationDriver>();
        }
        private static void UpdateInput() => InputSystem.Update();
        private static void Check(bool value, string message)
        {
            assertions++;
            if (!value) throw new Exception(message);
        }

        public static void Run()
        {
            try
            {
                XboxControllers.Shutdown();
                var pluginPath = "Packages/com.toyamakou11.xb-controller/Runtime/Plugins/x86_64/XbControllerNative.dll";
                AssetDatabase.ImportAsset(pluginPath, ImportAssetOptions.ForceUpdate);
                var importer = AssetImporter.GetAtPath(pluginPath) as PluginImporter;
                Check(importer != null && importer.GetCompatibleWithEditor(), "DLL Editor 設定");
                Check(importer.GetCompatibleWithPlatform(BuildTarget.StandaloneWindows64) &&
                    !importer.GetCompatibleWithPlatform(BuildTarget.StandaloneLinux64) &&
                    !importer.GetCompatibleWithPlatform(BuildTarget.StandaloneOSX), "DLL OS 設定");
                Check(Marshal.SizeOf<NativeSnapshot>() == 80, "ABI サイズ");
                Check(NativeApi.xb_initialize(99, 80) < 0, "ABI バージョン拒否");
                Check(NativeApi.xb_initialize(1, 79) < 0, "ABI サイズ拒否");
                Check(NativeApi.xb_shutdown() == 0 && NativeApi.xb_shutdown() == 0, "終了の冪等性");
                Check(NativeApi.xb_poll(Array.Empty<NativeSnapshot>(), 0, out _, out _) < 0, "未初期化拒否");
                InputSystem.settings.updateMode = InputSettings.UpdateMode.ProcessEventsManually;
                InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
                InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
                Application.runInBackground = true;
                XboxControllers.Initialize(ControllerBackend.UnityInputSystem);
                typeof(XboxControllers).GetMethod("FocusChanged", BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, new object[] { true });
                InputSystem.RegisterLayout<RecordingGamepad>();
                var rumbleDevice = InputSystem.AddDevice<RecordingGamepad>();
                Controller rumble = null;
                foreach (var item in XboxControllers.All) if (item.UnityDevice == rumbleDevice) rumble = item;
                Check(rumble != null && rumble.SupportedRumbleMotors == 3, "Unity 振動能力");
                int motorCalls = rumbleDevice.MotorCalls;
                rumble.StopRumble();
                Check(rumbleDevice.MotorCalls == motorCalls, "未所有の振動に触れない");
                Check(rumble.SetRumble(2, -1, -1, -2) && rumbleDevice.Low == 1 && rumbleDevice.High == 0,
                    "有限値の制限と非対応負値の中立化");
                motorCalls = rumbleDevice.MotorCalls;
                Check(!rumble.SetRumble(float.NaN, 0) && !rumble.SetRumble(0, float.PositiveInfinity) &&
                    !rumble.SetRumble(0, 0, 0.1f) && rumbleDevice.MotorCalls == motorCalls,
                    "不正値と非対応出力は既存出力を変更しない");
                var rumbleFocus = typeof(XboxControllers).GetMethod("FocusChanged", BindingFlags.NonPublic | BindingFlags.Static);
                rumbleFocus.Invoke(null, new object[] { false });
                Check(rumbleDevice.MotorCalls == motorCalls + 1 && rumbleDevice.Low == 0 && rumbleDevice.High == 0,
                    "フォーカス喪失で所有出力を停止");
                Check(!rumble.SetRumble(1, 1), "背景振動要求を拒否");
                rumbleFocus.Invoke(null, new object[] { true });
                Check(rumbleDevice.MotorCalls == motorCalls + 1, "復帰で自動再開しない");
                Check(rumble.SetRumble(0.2f, 0.3f), "明示的な再開");
                InputSystem.DisableDevice(rumbleDevice);
                Check(!rumble.IsConnected && rumbleDevice.Low == 0 && rumbleDevice.High == 0 &&
                    !rumble.SetRumble(1, 1), "無効化で停止し古い参照を拒否");
                InputSystem.RemoveDevice(rumbleDevice);
                var first = InputSystem.AddDevice<Gamepad>();
                var second = InputSystem.AddDevice<Gamepad>();
                Controller pad = null;
                foreach (var item in XboxControllers.All) if (item.UnityDevice == first) pad = item;
                Check(pad != null, "接続通知");
                Check(!pad.Supports(XboxButton.Paddles), "非対応パドルを偽装しない");
                var unityButtons = new[] { GamepadButton.Start, GamepadButton.Select, GamepadButton.A, GamepadButton.B,
                    GamepadButton.X, GamepadButton.Y, GamepadButton.DpadUp, GamepadButton.DpadDown,
                    GamepadButton.DpadLeft, GamepadButton.DpadRight, GamepadButton.LeftShoulder, GamepadButton.RightShoulder,
                    GamepadButton.LeftStick, GamepadButton.RightStick };
                var xboxButtons = new[] { XboxButton.Menu, XboxButton.View, XboxButton.A, XboxButton.B,
                    XboxButton.X, XboxButton.Y, XboxButton.DpadUp, XboxButton.DpadDown,
                    XboxButton.DpadLeft, XboxButton.DpadRight, XboxButton.LeftShoulder, XboxButton.RightShoulder,
                    XboxButton.LeftStickClick, XboxButton.RightStickClick };
                InputSystem.QueueStateEvent(first, new GamepadState());
                UpdateInput();
                for (int i = 0; i < unityButtons.Length; i++)
                {
                    // Unity の初回 edge 追跡を温める。
                    pad.WasPressed(xboxButtons[i]); pad.WasReleased(xboxButtons[i]);
                    InputSystem.QueueStateEvent(first, new GamepadState().WithButton(unityButtons[i]));
                    UpdateInput();
                    Check(pad.IsPressed(xboxButtons[i]) && pad.WasPressed(xboxButtons[i]), "標準押下 " + xboxButtons[i]
                        + " wrapper=" + pad.IsPressed(xboxButtons[i]) + "/" + pad.WasPressed(xboxButtons[i])
                        + " control=" + first[unityButtons[i]].isPressed + "/" + first[unityButtons[i]].wasPressedThisFrame
                        + " connected=" + pad.IsConnected + " focus=" + XboxControllers.HasFocus + " update=" + InputState.currentUpdateType);
                    InputSystem.QueueStateEvent(first, new GamepadState()); UpdateInput();
                    Check(!pad.IsPressed(xboxButtons[i]) && pad.WasReleased(xboxButtons[i]), "標準解放 " + xboxButtons[i]);
                }
                InputSystem.QueueStateEvent(first, new GamepadState { leftStick = new Vector2(1, 0), rightStick = new Vector2(0, 1), leftTrigger = 1, rightTrigger = 0.75f });
                UpdateInput();
                Check(pad.LeftStick.x > 0.99f && pad.RightStick.y > 0.99f, "スティック");
                Check(pad.LeftTrigger == 1 && pad.RightTrigger == 0.75f && pad.IsPressed(XboxButton.LeftTrigger), "トリガー");
                Check(pad.IsPressed(XboxButton.LeftStickRight) && pad.IsPressed(XboxButton.RightStickUp), "スティック方向");
                Benchmark(pad);
                InputSystem.DisableDevice(first);
                Check(!pad.IsConnected && pad.LeftTrigger == 0 && !pad.IsPressed(XboxButton.A), "無効化後は中立");
                InputSystem.EnableDevice(first);
                Controller replacement = null;
                foreach (var item in XboxControllers.All) if (item.UnityDevice == first) replacement = item;
                Check(replacement != null && !ReferenceEquals(pad, replacement), "再有効化で新参照");
                InputSystem.RemoveDevice(first); InputSystem.RemoveDevice(second);
                Check(!replacement.IsConnected && replacement.LeftStick == Vector2.zero, "切断済み参照");

                var snapshot = new NativeSnapshot { Token = 12, Supported = ulong.MaxValue, Rumble = 15 };
                var native = new Controller(snapshot);
                foreach (XboxButton button in Enum.GetValues(typeof(XboxButton)))
                {
                    if (button == XboxButton.None) continue;
                    snapshot.Buttons = snapshot.Pressed = snapshot.Released = (ulong)button;
                    native.Update(snapshot);
                    Check(native.Supports(button) && native.IsPressed(button) && native.WasPressed(button) && native.WasReleased(button), "native フラグ " + button);
                }
                snapshot.Buttons = 0;
                snapshot.Pressed = snapshot.Released = (ulong)XboxButton.Paddles;
                native.Update(snapshot);
                Check(!native.IsPressed(XboxButton.Paddles) && native.WasPressed(XboxButton.Paddles) && native.WasReleased(XboxButton.Paddles), "短い押下の両エッジ");
                snapshot.Error = unchecked((int)0x80004005); native.Update(snapshot);
                Check(!native.WasPressed(XboxButton.Paddles) && native.LeftTrigger == 0, "取得失敗は中立");
                snapshot.Error = NativeApi.HistoryResync; native.Update(snapshot);
                Check(native.WasPressed(XboxButton.Paddles), "履歴再同期後の有効値");
                Check(!native.SetRumble(float.NaN, 0), "不正振動値");
                native.Invalidate();
                Check(!native.IsConnected && native.LeftStick == Vector2.zero, "native 古い参照");

                var focusMethod = typeof(XboxControllers).GetMethod("FocusChanged", BindingFlags.NonPublic | BindingFlags.Static);
                focusMethod.Invoke(null, new object[] { false });
                var benchSnapshot = new NativeSnapshot { Token = 20, Supported = (ulong)XboxButton.Paddles, Buttons = (ulong)XboxButton.Paddles, LeftX = 0.5f };
                var bench = new Controller(benchSnapshot);
                Check(!bench.IsPressed(XboxButton.Paddles), "フォーカス喪失");
                focusMethod.Invoke(null, new object[] { true });
                Benchmark(bench);
                var registry = (System.Collections.Generic.List<Controller>)typeof(XboxControllers)
                    .GetField("controllers", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
                benchSnapshot.Pressed = benchSnapshot.Released = (ulong)XboxButton.Paddles;
                benchSnapshot.LeftTrigger = 1;
                bench.Update(benchSnapshot);
                registry.Add(bench);
                focusMethod.Invoke(null, new object[] { false });
                focusMethod.Invoke(null, new object[] { true });
                Check(registry.Contains(bench) && bench.IsConnected && !bench.IsPressed(XboxButton.Paddles) &&
                    !bench.WasPressed(XboxButton.Paddles) && !bench.WasReleased(XboxButton.Paddles) &&
                    bench.LeftStick == Vector2.zero && bench.LeftTrigger == 0, "フォーカス復帰時のキャッシュ中立化");
                registry.Remove(bench);
                XboxControllers.Shutdown(); XboxControllers.Initialize(ControllerBackend.UnityInputSystem);
                XboxControllers.Shutdown(); XboxControllers.Shutdown();
                VerifySetup();
                File.WriteAllText(Path.Combine(Application.dataPath, "../verification-result.txt"), $"PASS assertions={assertions}\n");
                Debug.Log($"検証成功: {assertions} assertions");
                EditorApplication.Exit(0);
            }
            catch (Exception error) { Debug.LogException(error); EditorApplication.Exit(1); }
        }

        private static void Benchmark(Controller pad)
        {
            float checksum = 0;
            for (int i = 0; i < 10000; i++) checksum += pad.LeftStick.x;
            var watch = new Stopwatch();
            for (int trial = 0; trial < 5; trial++)
            {
                long before = GC.GetAllocatedBytesForCurrentThread();
                watch.Restart();
                for (int i = 0; i < 100000; i++)
                {
                    checksum += pad.LeftStick.x + pad.RightStick.y + pad.LeftTrigger + pad.RightTrigger;
                    if (pad.IsPressed(XboxButton.PaddleLeft1)) checksum += 1;
                    pad.WasPressed(XboxButton.PaddleRight1); pad.WasReleased(XboxButton.PaddleRight2);
                }
                watch.Stop();
                long bytes = GC.GetAllocatedBytesForCurrentThread() - before;
                Check(bytes == 0, "定常読み取りの割り当て " + bytes);
                Debug.Log($"測定 backend={pad.Backend} trial={trial} iterations=100000 bytes={bytes} ms={watch.Elapsed.TotalMilliseconds:F3} checksum={checksum}");
            }
        }

        private static void VerifySetup()
        {
            var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            var settings = new SerializedObject(assets[0]);
            var property = settings.FindProperty("activeInputHandler");
            foreach (int value in new[] { 0, 1, 2 })
            {
                property.intValue = value; settings.ApplyModifiedPropertiesWithoutUndo();
                ControllerSetup.EnableInput(); settings.Update();
                Check(property.intValue == (value == 0 ? 2 : value), "自動設定 " + value);
                ControllerSetup.EnableInput(); settings.Update();
                Check(property.intValue == (value == 0 ? 2 : value), "設定冪等 " + value);
            }
        }
    }
}
