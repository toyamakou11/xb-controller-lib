using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using XbController;

namespace XbController.Verification
{
    public sealed class PlayerRecordingGamepad : Gamepad
    {
        public float Low, High;
        public override void SetMotorSpeeds(float lowFrequency, float highFrequency) { Low = lowFrequency; High = highFrequency; }
    }
    public sealed class PlayerVerification : MonoBehaviour
    {
        private int assertions;
        private void Check(bool value, string name) { assertions++; if (!value) throw new Exception(name); }
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void StartTest() => new GameObject("Player検証").AddComponent<PlayerVerification>();
        private void Update()
        {
            enabled = false;
            int exit = 1;
            try
            {
                string[] args = Environment.GetCommandLineArgs();
                int resultIndex = Array.IndexOf(args, "-result");
                if (resultIndex < 0 || resultIndex + 1 >= args.Length || args[resultIndex + 1].StartsWith("-"))
                    throw new ArgumentException("-result と結果ファイルのパスが必要です。");
                string result = args[resultIndex + 1];
                bool fallback = args.Contains("-expect-fallback");
                XboxControllers.Shutdown();
                Check(IntPtr.Size == 8 && Marshal.SizeOf<NativeSnapshot>() == 80, "x64 ABI");
                if (!fallback)
                {
                    Check(NativeApi.xb_initialize(99, 80) < 0, "ABI version拒否");
                    Check(NativeApi.xb_initialize(1, 79) < 0, "ABI size拒否");
                }
                XboxControllers.Initialize();
                Check(XboxControllers.Backend == (fallback ? ControllerBackend.UnityInputSystem : ControllerBackend.WindowsGameInput), "backend選択");
                Check(fallback ? XboxControllers.BackendError == unchecked((int)0x8007007E) : XboxControllers.BackendError >= 0, "backend診断");
                Debug.Log($"native backend={XboxControllers.Backend} error=0x{XboxControllers.BackendError:X8} devices={XboxControllers.All.Count}");
                XboxControllers.Shutdown();
                Check(XboxControllers.ShutdownError >= 0, "native終了");
                InputSystem.settings.updateMode = InputSettings.UpdateMode.ProcessEventsManually;
                InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
                XboxControllers.Initialize(ControllerBackend.UnityInputSystem);
                typeof(XboxControllers).GetMethod("FocusChanged", BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { true });
                InputSystem.RegisterLayout<PlayerRecordingGamepad>();
                var device = InputSystem.AddDevice<PlayerRecordingGamepad>();
                var pad = XboxControllers.All.First(p => p.UnityDevice == device);
                foreach (XboxButton button in new[] { XboxButton.A, XboxButton.B, XboxButton.X, XboxButton.Y })
                {
                    GamepadButton control = button == XboxButton.A ? GamepadButton.A : button == XboxButton.B ? GamepadButton.B : button == XboxButton.X ? GamepadButton.X : GamepadButton.Y;
                    pad.WasPressed(button); pad.WasReleased(button);
                    InputSystem.QueueStateEvent(device, new GamepadState().WithButton(control)); InputSystem.Update();
                    Check(pad.IsPressed(button) && pad.WasPressed(button), "合成押下 " + button);
                    InputSystem.QueueStateEvent(device, new GamepadState()); InputSystem.Update();
                    Check(!pad.IsPressed(button) && pad.WasReleased(button), "合成解放 " + button);
                }
                InputSystem.QueueStateEvent(device, new GamepadState { leftStick = new Vector2(1, 0), rightStick = new Vector2(0, 1), leftTrigger = 1, rightTrigger = 0.75f }); InputSystem.Update();
                Check(pad.LeftStick.x > 0.99f && pad.RightStick.y > 0.99f, "合成stick");
                Check(pad.LeftTrigger == 1 && pad.RightTrigger == 0.75f, "合成trigger");
                Check(pad.SetRumble(0.2f, 0.3f) && device.Low == 0.2f && device.High == 0.3f, "合成rumble");
                pad.StopRumble();
                Check(device.Low == 0 && device.High == 0, "合成rumble停止");
                Check(pad.SetRumble(0.1f, 0.1f), "合成rumble再要求");
                XboxControllers.Shutdown();
                Check(!pad.IsConnected && pad.LeftStick == Vector2.zero && device.Low == 0 && device.High == 0, "終了後の中立と所有rumble停止");
                InputSystem.RemoveDevice(device);
                XboxControllers.Shutdown();
                File.WriteAllText(result, $"PASS assertions={assertions} fallback={fallback}\n");
                Debug.Log($"Player検証成功 assertions={assertions} fallback={fallback}");
                exit = 0;
            }
            catch (Exception error) { Debug.LogException(error); }
            finally { XboxControllers.Shutdown(); Application.Quit(exit); }
        }
    }
}
