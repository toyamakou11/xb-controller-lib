using System.Runtime.InteropServices;

namespace XbController
{
    [StructLayout(LayoutKind.Sequential, Pack = 8)]
    internal struct NativeSnapshot
    {
        public ulong Token, Timestamp, Supported, Buttons, Pressed, Released;
        public uint Rumble;
        public int Error;
        public float LeftTrigger, RightTrigger, LeftX, LeftY, RightX, RightY;
    }

    internal static class NativeApi
    {
        internal const uint Version = 1;
        internal const int InsufficientBuffer = unchecked((int)0x8007007A);
        internal const int HistoryResync = unchecked((int)0x838A0004);
        private const string Library = "XbControllerNative";
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int xb_initialize(uint version, uint size);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int xb_shutdown();
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int xb_poll([Out] NativeSnapshot[] buffer, uint capacity, out uint count, out int diagnostic);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int xb_rumble(ulong token, float low, float high, float left, float right);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void xb_resync();
    }
}
