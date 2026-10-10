using System;

namespace XbController
{
    // 下位32bitは GameInput v3、上位は system callback 用。
    [Flags]
    public enum XboxButton : ulong
    {
        None = 0,
        Menu = 0x00000001, View = 0x00000002,
        A = 0x00000004, B = 0x00000008, X = 0x00000010, Y = 0x00000020,
        DpadUp = 0x00000040, DpadDown = 0x00000080,
        DpadLeft = 0x00000100, DpadRight = 0x00000200,
        LeftShoulder = 0x00000400, RightShoulder = 0x00000800,
        LeftStickClick = 0x00001000, RightStickClick = 0x00002000,
        C = 0x00004000, Z = 0x00008000,
        LeftTrigger = 0x00010000, RightTrigger = 0x00020000,
        LeftStickUp = 0x00040000, LeftStickDown = 0x00080000,
        LeftStickLeft = 0x00100000, LeftStickRight = 0x00200000,
        RightStickUp = 0x00400000, RightStickDown = 0x00800000,
        RightStickLeft = 0x01000000, RightStickRight = 0x02000000,
        Guide = 1UL << 32, Share = 1UL << 33
    }

    public enum ControllerBackend { UnityInputSystem, WindowsGameInput }
}
