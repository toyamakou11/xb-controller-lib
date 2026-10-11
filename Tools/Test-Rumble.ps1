[CmdletBinding()]
param([switch]$ListOnly)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $repository 'Runtime/Plugins/x86_64/XbControllerNative.dll'
$source = @'
using System;
using System.Runtime.InteropServices;
public static class XbRumbleTest {
 [StructLayout(LayoutKind.Sequential, Pack=8)] public struct Snapshot {
  public ulong Token,Timestamp,Supported,Buttons,Pressed,Released;
  public uint Rumble; public int Error;
  public float LeftTrigger,RightTrigger,LeftX,LeftY,RightX,RightY;
 }
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_initialize(uint version,uint size);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_poll([Out] Snapshot[] states,uint capacity,out uint count,out int diagnostic);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_rumble(ulong token,float low,float high,float left,float right);
 [DllImport("__DLL__",CallingConvention=CallingConvention.Cdecl)] public static extern int xb_shutdown();
}
'@
Add-Type -TypeDefinition $source.Replace('__DLL__',$dll.Replace('\','\\'))
function Read-Controllers {
    $buffer = [XbRumbleTest+Snapshot[]]::new(0)
    [uint32]$count = 0; [int]$diagnostic = 0
    do {
        $hr = [XbRumbleTest]::xb_poll($buffer,$buffer.Length,[ref]$count,[ref]$diagnostic)
        if ($hr -eq -2147024774) { $buffer = [XbRumbleTest+Snapshot[]]::new($count) }
    } while ($hr -eq -2147024774)
    if ($hr -lt 0 -or $diagnostic -lt 0) { throw ('読み取り診断: 0x{0:X8}/0x{1:X8}' -f $hr,$diagnostic) }
    for ($i=0; $i -lt $count; $i++) { $buffer[$i] }
}
$hr = [XbRumbleTest]::xb_initialize(1,[Runtime.InteropServices.Marshal]::SizeOf([type][XbRumbleTest+Snapshot]))
if ($hr -lt 0) { throw ('初期化失敗: 0x{0:X8}' -f $hr) }
[uint64]$selected = 0
$ownsOutput = $false
try {
    $devices = @(Read-Controllers)
    foreach ($device in $devices) { 'Connection={0} MotorMask=0x{1:X} ReadError=0x{2:X8}' -f $device.Token,$device.Rumble,$device.Error }
    if ($ListOnly -or $devices.Count -eq 0) { return }
    # token はこのセッション内だけで有効。
    $choice = Read-Host 'このセッションの Connection を選択（空欄で終了）'
    if (-not $choice) { return }
    if (-not [uint64]::TryParse($choice,[ref]$selected) -or -not ($devices.Token -contains $selected)) { throw '選択が無効です。' }
    $transport = Read-Host '実際の接続方法（USB-C / Bluetooth）'
    '要求の成功は実機振動の証明ではありません。選択端末を手に持ち、各案内の Enter 後に観測してください。'
    $names = @('LowFrequency 本体左','HighFrequency 本体右','LeftTrigger 左トリガー','RightTrigger 右トリガー')
    for ($motor=0; $motor -lt $names.Length; $motor++) {
        $device = @(Read-Controllers | Where-Object Token -eq $selected)
        # 履歴再同期は致命的エラーではない。
        $historyResync = -2088108028 # GAMEINPUT_E_REFERENCE_READING_TOO_OLD (0x838A0004)
        if ($device.Count -ne 1 -or ($device[0].Error -lt 0 -and $device[0].Error -ne $historyResync)) { throw '選択端末の接続・読み取りを確認できません。' }
        if (($device[0].Rumble -band (1 -shl $motor)) -eq 0) { "$($names[$motor]): metadata 非対応、出力なし"; continue }
        $null = Read-Host ($names[$motor]+' を0.25で700ms試験。Enterで開始、Ctrl+Cで中止')
        $levels = [single[]]::new(4); $levels[$motor] = 0.25
        $hr = [XbRumbleTest]::xb_rumble($selected,$levels[0],$levels[1],$levels[2],$levels[3])
        if ($hr -lt 0) { throw ('出力要求失敗: 0x{0:X8}' -f $hr) }
        $ownsOutput = $true
        Start-Sleep -Milliseconds 700
        $stop = [XbRumbleTest]::xb_rumble($selected,0,0,0,0)
        if ($stop -ge 0) { $ownsOutput = $false }
        'Motor={0} Transport={1} Request=0x{2:X8} Stop=0x{3:X8}' -f $names[$motor],$transport,$hr,$stop
        if ($stop -lt 0) { throw '停止要求失敗。終了処理でも再試行します。' }
        $observation = Read-Host '実機観測（振動した位置・他モーターの有無・停止したか）'
        [pscustomobject]@{Motor=$names[$motor];Transport=$transport;PhysicalObservation=$observation} | ConvertTo-Json -Compress
    }
} finally {
    if ($ownsOutput) { $null = [XbRumbleTest]::xb_rumble($selected,0,0,0,0) }
    $shutdown = [XbRumbleTest]::xb_shutdown()
    if ($shutdown -lt 0) { Write-Warning ('終了失敗: 0x{0:X8}' -f $shutdown) }
}
