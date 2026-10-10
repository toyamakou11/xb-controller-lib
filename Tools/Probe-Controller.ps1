[CmdletBinding()]
param([ValidateRange(0,300)][int]$Seconds = 0)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $repository 'Runtime/Plugins/x86_64/XbControllerNative.dll'
$source = @'
using System;
using System.Runtime.InteropServices;
public static class XbControllerProbe {
 [StructLayout(LayoutKind.Sequential, Pack=8)] public struct Snapshot {
  public ulong Token,Timestamp,Supported,Buttons,Pressed,Released;
  public uint Rumble; public int Error;
  public float LeftTrigger,RightTrigger,LeftX,LeftY,RightX,RightY;
 }
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_initialize(uint version,uint size);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_poll([Out] Snapshot[] states,uint capacity,out uint count,out int diagnostic);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_shutdown();
}
'@
Add-Type -TypeDefinition $source.Replace('__DLL__',$dll.Replace('\','\\'))
$hr = [XbControllerProbe]::xb_initialize(1,80)
if ($hr -lt 0) { throw ('GameInput v3 初期化失敗: 0x{0:X8}' -f $hr) }
try {
    $buffer = [XbControllerProbe+Snapshot[]]::new(0)
    [uint32]$count = 0; [int]$diagnostic = 0
    $hr = [XbControllerProbe]::xb_poll($buffer,0,[ref]$count,[ref]$diagnostic)
    if ($hr -eq -2147024774) { $buffer=[XbControllerProbe+Snapshot[]]::new($count) }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $first=$true
    do {
        $hr=[XbControllerProbe]::xb_poll($buffer,$buffer.Length,[ref]$count,[ref]$diagnostic)
        if ($hr -eq -2147024774) { $buffer=[XbControllerProbe+Snapshot[]]::new($count); continue }
        if ($hr -lt 0) { throw ('読み取り失敗: 0x{0:X8}' -f $hr) }
        if ($first) { '接続台数: '+$count; 'callback 診断: 0x{0:X8}' -f $diagnostic }
        for ($i=0;$i -lt $count;$i++) {
            $state=$buffer[$i]
            if ($first -or $state.Pressed -or $state.Released) {
                [pscustomobject]@{Token=$state.Token;Supported=('0x{0:X16}' -f $state.Supported);Buttons=('0x{0:X16}' -f $state.Buttons);Pressed=('0x{0:X16}' -f $state.Pressed);Released=('0x{0:X16}' -f $state.Released);Error=('0x{0:X8}' -f $state.Error)} | ConvertTo-Json -Compress
            }
        }
        $first=$false
        if ($Seconds -gt 0) { Start-Sleep -Milliseconds 10 }
    } while ($watch.Elapsed.TotalSeconds -lt $Seconds)
} finally {
    $shutdown=[XbControllerProbe]::xb_shutdown()
    if ($shutdown -lt 0) { Write-Warning ('終了失敗: 0x{0:X8}' -f $shutdown) }
}
