using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace XbController
{
    public static class XboxControllers
    {
        private static readonly List<Controller> controllers = new List<Controller>();
        private static readonly IReadOnlyList<Controller> view = controllers.AsReadOnly();
        private static NativeSnapshot[] buffer = Array.Empty<NativeSnapshot>();
        private static bool initialized;
        public static ControllerBackend Backend { get; private set; }
        public static int BackendError { get; private set; }
        public static int ShutdownError { get; private set; }
        public static bool HasFocus { get; private set; } = true;
        public static IReadOnlyList<Controller> All { get { Initialize(); return view; } }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void Reset() { Shutdown(); Initialize(); }

        public static void Initialize(ControllerBackend preferredBackend = ControllerBackend.WindowsGameInput)
        {
            if (initialized) return;
            Backend = ControllerBackend.UnityInputSystem;
            BackendError = 0;
            HasFocus = !Application.isPlaying || Application.isFocused;
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
            if (preferredBackend == ControllerBackend.WindowsGameInput) try
            {
                BackendError = NativeApi.xb_initialize(NativeApi.Version, (uint)Marshal.SizeOf<NativeSnapshot>());
                if (BackendError >= 0) Backend = ControllerBackend.WindowsGameInput;
            }
            catch (DllNotFoundException) { BackendError = unchecked((int)0x8007007E); }
            catch (EntryPointNotFoundException) { BackendError = unchecked((int)0x8007007F); }
            catch (BadImageFormatException) { BackendError = unchecked((int)0x8007000B); }
#endif
            initialized = true;
            InputSystem.onBeforeUpdate += BeforeUpdate;
            InputSystem.onDeviceChange += DeviceChanged;
            Application.focusChanged += FocusChanged;
            Application.quitting += Shutdown;
            if (Backend == ControllerBackend.UnityInputSystem) RefreshUnity();
            else PollNative();
        }

        private static void BeforeUpdate()
        {
            var type = InputState.currentUpdateType;
            bool selected = Application.isPlaying
                ? (InputSystem.settings.updateMode == InputSettings.UpdateMode.ProcessEventsManually
                    ? type == InputUpdateType.Manual : InputSystem.settings.updateMode == InputSettings.UpdateMode.ProcessEventsInFixedUpdate
                        ? type == InputUpdateType.Fixed : type == InputUpdateType.Dynamic)
                : type == InputUpdateType.Editor || type == InputUpdateType.Dynamic || type == InputUpdateType.Manual;
            if (selected && HasFocus && Backend == ControllerBackend.WindowsGameInput) PollNative();
        }

        private static void PollNative()
        {
            uint count;
            int result = NativeApi.xb_poll(buffer, (uint)buffer.Length, out count, out int diagnostic);
            if (result == NativeApi.InsufficientBuffer)
            {
                // 台数増加時だけ拡張し、通常更新では同じ配列を再利用する。
                buffer = new NativeSnapshot[count];
                result = NativeApi.xb_poll(buffer, (uint)buffer.Length, out count, out diagnostic);
            }
            if (result < 0)
            {
                BackendError = result;
                Clear();
                return;
            }
            BackendError = diagnostic;
            for (int i = controllers.Count - 1; i >= 0; i--)
            {
                bool found = false;
                for (int j = 0; j < count; j++) if (controllers[i].ConnectionId == buffer[j].Token) { found = true; break; }
                if (!found) { controllers[i].Invalidate(); controllers.RemoveAt(i); }
            }
            for (int j = 0; j < count; j++)
            {
                Controller existing = null;
                for (int i = 0; i < controllers.Count; i++) if (controllers[i].ConnectionId == buffer[j].Token) { existing = controllers[i]; break; }
                if (existing == null) controllers.Add(new Controller(buffer[j]));
                else existing.Update(buffer[j]);
            }
        }

        private static void DeviceChanged(InputDevice device, InputDeviceChange change)
        {
            if (Backend == ControllerBackend.UnityInputSystem && device is Gamepad) RefreshUnity();
        }

        private static void RefreshUnity()
        {
            for (int i = controllers.Count - 1; i >= 0; i--)
            {
                var controller = controllers[i];
                if (!controller.IsConnected) { controller.Invalidate(); controllers.RemoveAt(i); }
            }
            var pads = Gamepad.all;
            for (int j = 0; j < pads.Count; j++)
            {
                var pad = pads[j];
                if (!pad.enabled) continue;
                bool found = false;
                for (int i = 0; i < controllers.Count; i++) if (controllers[i].UnityDevice == pad) { found = true; break; }
                if (!found) controllers.Add(new Controller(pad));
            }
        }

        private static void FocusChanged(bool focused)
        {
            foreach (var controller in controllers)
            {
                controller.StopRumble();
                controller.Neutralize();
            }
            if (Backend == ControllerBackend.WindowsGameInput) NativeApi.xb_resync();
            HasFocus = focused;
        }

        private static void Clear()
        {
            for (int i = 0; i < controllers.Count; i++) controllers[i].Invalidate();
            controllers.Clear();
        }

        public static void Shutdown()
        {
            if (!initialized) return;
            InputSystem.onBeforeUpdate -= BeforeUpdate;
            InputSystem.onDeviceChange -= DeviceChanged;
            Application.focusChanged -= FocusChanged;
            Application.quitting -= Shutdown;
            Clear();
            if (Backend == ControllerBackend.WindowsGameInput) ShutdownError = NativeApi.xb_shutdown();
            initialized = false;
        }
    }
}
