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
    $deviceStats=@{}
    do {
        $hr=[XbControllerProbe]::xb_poll($buffer,$buffer.Length,[ref]$count,[ref]$diagnostic)
        if ($hr -eq -2147024774) { $buffer=[XbControllerProbe+Snapshot[]]::new($count); continue }
        if ($hr -lt 0) { throw ('読み取り失敗: 0x{0:X8}' -f $hr) }
        for ($i=0;$i -lt $count;$i++) {
            $state=$buffer[$i]
            $key=[string]$state.Token
            if (-not $deviceStats.ContainsKey($key)) {
                $deviceStats[$key]=@{Supported=$state.Supported;Pressed=[uint64]0;Released=[uint64]0;Error=$state.Error;Minimum=@{};Maximum=@{}}
            }
            $stats=$deviceStats[$key]
            $stats.Pressed=$stats.Pressed -bor [uint64]$state.Pressed
            $stats.Released=$stats.Released -bor [uint64]$state.Released
            $stats.Error=$state.Error
            $axes=@{LeftTrigger=$state.LeftTrigger;RightTrigger=$state.RightTrigger;LeftX=$state.LeftX;LeftY=$state.LeftY;RightX=$state.RightX;RightY=$state.RightY}
            foreach ($axis in $axes.Keys) {
                $value=[double]$axes[$axis]
                if (-not $stats.Minimum.ContainsKey($axis) -or $value -lt $stats.Minimum[$axis]) { $stats.Minimum[$axis]=$value }
                if (-not $stats.Maximum.ContainsKey($axis) -or $value -gt $stats.Maximum[$axis]) { $stats.Maximum[$axis]=$value }
            }
        }
        if ($Seconds -gt 0) { Start-Sleep -Milliseconds 10 }
    } while ($watch.Elapsed.TotalSeconds -lt $Seconds)
    foreach ($key in $deviceStats.Keys) {
        $stats=$deviceStats[$key]
        $ranges=[ordered]@{}
        foreach ($axis in $stats.Minimum.Keys) { $ranges[$axis]=@([Math]::Round($stats.Minimum[$axis],3),[Math]::Round($stats.Maximum[$axis],3)) }
        [pscustomobject]@{Token=[uint64]$key;Supported=('0x{0:X16}' -f $stats.Supported);Pressed=('0x{0:X16}' -f $stats.Pressed);Released=('0x{0:X16}' -f $stats.Released);AxisRanges=$ranges;Error=('0x{0:X8}' -f $stats.Error)} | ConvertTo-Json -Compress -Depth 4
    }
    '接続台数: '+$count
    'callback 診断: 0x{0:X8}' -f $diagnostic
} finally {
    $shutdown=[XbControllerProbe]::xb_shutdown()
    if ($shutdown -lt 0) { Write-Warning ('終了失敗: 0x{0:X8}' -f $shutdown) }
}
