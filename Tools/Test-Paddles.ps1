# 公開 ABI を読み取り、標準ボタンと独立 paddle の状態・edge を別々に記録する。
[CmdletBinding()]
param([ValidateRange(1,600)][int]$Seconds = 120, [switch]$ResyncWhileHeld, [string]$StopFile)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $repository 'Runtime/Plugins/x86_64/XbControllerNative.dll'
$source = @'
using System;
using System.Runtime.InteropServices;
public static class XbPaddleTest {
 [StructLayout(LayoutKind.Sequential,Pack=8)] public struct Snapshot {
  public ulong Token,Timestamp,Supported,Buttons,Pressed,Released;
  public uint Rumble; public int Error;
  public float LeftTrigger,RightTrigger,LeftX,LeftY,RightX,RightY;
 }
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_initialize(uint version,uint size);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_poll([Out] Snapshot[] states,uint capacity,out uint count,out int diagnostic);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_shutdown();
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern void xb_resync();
}
'@
Add-Type -TypeDefinition $source.Replace('__DLL__',$dll.Replace('\','\\'))
$hr = [XbPaddleTest]::xb_initialize(1,80)
if ($hr -lt 0) { throw ('初期化失敗: 0x{0:X8}' -f $hr) }
try {
    $buffer = [XbPaddleTest+Snapshot[]]::new(0)
    $previous = @{}
    [uint32]$count = 0; [int]$diagnostic = 0
    [long]$polls = 0
    $resynced = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    'CaptureReady Seconds={0} PaddleOrder=LeftUpper,LeftLower,RightUpper,RightLower' -f $Seconds
    while ($watch.Elapsed.TotalSeconds -lt $Seconds) {
        if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { break }
        $hr = [XbPaddleTest]::xb_poll($buffer,$buffer.Length,[ref]$count,[ref]$diagnostic)
        if ($hr -eq -2147024774) { $buffer = [XbPaddleTest+Snapshot[]]::new($count); continue }
        if ($hr -lt 0) { throw ('poll失敗: 0x{0:X8}' -f $hr) }
        ++$polls
        if ($ResyncWhileHeld -and !$resynced) {
            for ($i=0; $i -lt $count; ++$i) {
                if (($buffer[$i].Buttons -band 0x3C000000) -ne 0) {
                    [XbPaddleTest]::xb_resync()
                    'ResyncRequested Ms={0} Token={1} Held=0x{2:X}' -f [int]$watch.Elapsed.TotalMilliseconds,$buffer[$i].Token,(($buffer[$i].Buttons -shr 26) -band 15)
                    $resynced = $true
                    break
                }
            }
        }
        $present = @{}
        for ($i=0; $i -lt $count; ++$i) {
            $s = $buffer[$i]
            $present[$s.Token] = $true
            $key = '{0}:{1}:{2}:{3}' -f $s.Buttons,$s.Supported,$s.Error,$diagnostic
            if ($previous[$s.Token] -ne $key -or $s.Pressed -or $s.Released) {
                'Ms={0} Token={1} Paddles=0x{2:X} Pressed=0x{3:X} Released=0x{4:X} Standard=0x{5:X} Supported=0x{6:X} Error=0x{7:X8} Diagnostic=0x{8:X8}' -f [int]$watch.Elapsed.TotalMilliseconds,$s.Token,(($s.Buttons -shr 26) -band 15),(($s.Pressed -shr 26) -band 15),(($s.Released -shr 26) -band 15),($s.Buttons -band 0x3FFFFFF),$s.Supported,$s.Error,$diagnostic
                $previous[$s.Token] = $key
            }
        }
        foreach ($token in @($previous.Keys)) {
            if (!$present.ContainsKey($token)) { 'Disconnected Token={0}' -f $token; $previous.Remove($token) }
        }
        Start-Sleep -Milliseconds 5
    }
    'Polls={0} ElapsedMs={1}' -f $polls,[int]$watch.Elapsed.TotalMilliseconds
} finally {
    $stop = [XbPaddleTest]::xb_shutdown()
    'Shutdown=0x{0:X8}' -f $stop
    if ($stop -lt 0) { throw '終了処理に失敗しました。資源を保持しており、このプロセス内の再試行が必要です。' }
}
