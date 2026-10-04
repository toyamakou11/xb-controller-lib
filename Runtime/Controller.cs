using System;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
using UnityEngine.InputSystem.Processors;

namespace XbController
{
    public sealed class Controller
    {
        private readonly ButtonControl[] controls;
        private readonly XboxButton[] buttons;
        private readonly StickDeadzoneProcessor deadzone = new StickDeadzoneProcessor();
        private bool alive = true;
        private bool ownsRumble;
        private NativeSnapshot state;
        public ControllerBackend Backend { get; }
        public Gamepad UnityDevice { get; }
        public ulong ConnectionId { get; }
        public bool IsConnected => alive && (UnityDevice == null || (UnityDevice.added && UnityDevice.enabled));
        public int LastReadError => state.Error;
        public ulong TimestampMicroseconds => state.Timestamp;
        public XboxButton SupportedButtons { get; private set; }
        public uint SupportedRumbleMotors { get; private set; }
        private bool Readable => IsConnected && XboxControllers.HasFocus &&
            (UnityDevice != null || state.Error >= 0 || state.Error == NativeApi.HistoryResync);

        internal Controller(NativeSnapshot snapshot)
        {
            Backend = ControllerBackend.WindowsGameInput;
            ConnectionId = snapshot.Token;
            Update(snapshot);
        }

        internal Controller(Gamepad pad)
        {
            Backend = ControllerBackend.UnityInputSystem;
            UnityDevice = pad;
            ConnectionId = (ulong)pad.deviceId;
            // 機種番号ではなく Unity が保証する意味的 control を対応づける。
            buttons = new[] { XboxButton.Menu, XboxButton.View, XboxButton.A, XboxButton.B, XboxButton.X, XboxButton.Y,
                XboxButton.DpadUp, XboxButton.DpadDown, XboxButton.DpadLeft, XboxButton.DpadRight,
                XboxButton.LeftShoulder, XboxButton.RightShoulder, XboxButton.LeftStickClick, XboxButton.RightStickClick,
                XboxButton.LeftTrigger, XboxButton.RightTrigger,
                XboxButton.LeftStickUp, XboxButton.LeftStickDown, XboxButton.LeftStickLeft, XboxButton.LeftStickRight,
                XboxButton.RightStickUp, XboxButton.RightStickDown, XboxButton.RightStickLeft, XboxButton.RightStickRight };
            controls = new ButtonControl[] { pad.startButton, pad.selectButton, pad.aButton, pad.bButton, pad.xButton, pad.yButton,
                pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right,
                pad.leftShoulder, pad.rightShoulder, pad.leftStickButton, pad.rightStickButton,
                pad.leftTrigger, pad.rightTrigger,
                pad.leftStick.up, pad.leftStick.down, pad.leftStick.left, pad.leftStick.right,
                pad.rightStick.up, pad.rightStick.down, pad.rightStick.left, pad.rightStick.right };
            for (int i = 0; i < buttons.Length; i++) if (controls[i] != null) SupportedButtons |= buttons[i];
            // Unity の汎用 Gamepad は2モーターの出力 API を持つ。実機応答は別途確認が必要。
            SupportedRumbleMotors = 3;
        }

        internal void Update(NativeSnapshot snapshot)
        {
            state = snapshot;
            SupportedButtons = (XboxButton)snapshot.Supported;
            SupportedRumbleMotors = snapshot.Rumble;
        }

        public bool Supports(XboxButton button) => button != XboxButton.None && (SupportedButtons & button) == button;
        public bool IsPressed(XboxButton button) => Read(button, 0);
        public bool WasPressed(XboxButton button) => Read(button, 1);
        public bool WasReleased(XboxButton button) => Read(button, 2);

        private bool Read(XboxButton button, int kind)
        {
            if (!Readable || !Supports(button)) return false;
            if (UnityDevice == null)
            {
                ulong mask = kind == 0 ? state.Buttons : kind == 1 ? state.Pressed : state.Released;
                return (mask & (ulong)button) == (ulong)button;
            }
            for (int i = 0; i < buttons.Length; i++)
            {
                if ((buttons[i] & button) == 0) continue;
                var control = controls[i];
                bool value = kind == 0 ? control.isPressed : kind == 1 ? control.wasPressedThisFrame : control.wasReleasedThisFrame;
                if (!value) return false;
            }
            return true;
        }

        public Vector2 LeftStick => !Readable ? Vector2.zero : UnityDevice != null ? UnityDevice.leftStick.ReadValue()
            : deadzone.Process(new Vector2(state.LeftX, state.LeftY), null);
        public Vector2 RightStick => !Readable ? Vector2.zero : UnityDevice != null ? UnityDevice.rightStick.ReadValue()
            : deadzone.Process(new Vector2(state.RightX, state.RightY), null);
        public Vector2 Dpad => !Readable ? Vector2.zero : UnityDevice != null ? UnityDevice.dpad.ReadValue() :
            new Vector2((IsPressed(XboxButton.DpadRight) ? 1 : 0) - (IsPressed(XboxButton.DpadLeft) ? 1 : 0),
                (IsPressed(XboxButton.DpadUp) ? 1 : 0) - (IsPressed(XboxButton.DpadDown) ? 1 : 0)).normalized;
        public float LeftTrigger => !Readable ? 0 : UnityDevice != null ? UnityDevice.leftTrigger.ReadValue() : state.LeftTrigger;
        public float RightTrigger => !Readable ? 0 : UnityDevice != null ? UnityDevice.rightTrigger.ReadValue() : state.RightTrigger;

        public bool SetRumble(float low, float high, float leftTrigger = 0, float rightTrigger = 0)
        {
            if (!Readable || !Finite(low) || !Finite(high) || !Finite(leftTrigger) || !Finite(rightTrigger)) return false;
            if (UnityDevice == null)
            {
                if (NativeApi.xb_rumble(ConnectionId, low, high, leftTrigger, rightTrigger) < 0) return false;
            }
            else
            {
                if (leftTrigger != 0 || rightTrigger != 0) return false;
                UnityDevice.SetMotorSpeeds(Mathf.Clamp01(low), Mathf.Clamp01(high));
            }
            ownsRumble = Mathf.Clamp01(low) > 0 || Mathf.Clamp01(high) > 0 ||
                Mathf.Clamp01(leftTrigger) > 0 || Mathf.Clamp01(rightTrigger) > 0;
            return true;
        }

        private static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);
        internal void StopRumble()
        {
            if (!ownsRumble) return;
            if (UnityDevice == null) NativeApi.xb_rumble(ConnectionId, 0, 0, 0, 0);
            else if (UnityDevice.added) UnityDevice.SetMotorSpeeds(0, 0);
            ownsRumble = false;
        }

        internal void Invalidate() { StopRumble(); alive = false; state = default; }
        internal void Neutralize()
        {
            if (UnityDevice != null) return;
            state.Buttons = state.Pressed = state.Released = 0;
            state.LeftX = state.LeftY = state.RightX = state.RightY = state.LeftTrigger = state.RightTrigger = 0;
        }
    }
}
