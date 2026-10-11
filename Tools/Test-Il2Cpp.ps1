[CmdletBinding()]
param([Parameter(Mandatory)][string]$UnityEditor, [string]$CMake, [string]$SdkPath)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $repository '.verification/issue8-player'
$fixtures = Join-Path $repository 'Tests~/Player'
$project = Join-Path ([IO.Path]::GetTempPath()) 'xb-controller-lib-il2cpp-verification'
$inputPackage = Join-Path ([IO.Path]::GetTempPath()) 'xb-controller-lib-verification/inputsystem/package'
if (-not (Test-Path -LiteralPath "$inputPackage/package.json")) { throw '先に Tools/Test-Unity.ps1 を実行してください。' }
if (-not $SdkPath) { $SdkPath = Join-Path $repository '.verification/sdk' }
if (-not (Test-Path -LiteralPath "$SdkPath/native/include/GameInput.h")) { throw 'GameInput SDK の既存展開先を指定してください。' }
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installation)) { throw '既存の Visual Studio C++ ツールが必要です。' }
    $CMake = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
}
New-Item -ItemType Directory -Force $scratch,"$scratch/build","$project/Assets/Player","$project/Assets/Editor","$project/Packages","$project/ProjectSettings" | Out-Null
Copy-Item -LiteralPath "$fixtures/PlayerVerification.cs" -Destination "$project/Assets/Player/PlayerVerification.cs"
Copy-Item -LiteralPath "$fixtures/BuildVerification.cs" -Destination "$project/Assets/Editor/BuildVerification.cs"
'{"name":"XbController.Verification","references":["XbController.Runtime","Unity.InputSystem"]}' | Set-Content -LiteralPath "$project/Assets/Player/XbController.Verification.asmdef" -Encoding utf8
@{dependencies=@{
    'com.toyamakou11.xb-controller'='file:'+($repository -replace '\\','/')
    'com.unity.inputsystem'='file:'+($inputPackage -replace '\\','/')
}} | ConvertTo-Json | Set-Content -LiteralPath "$project/Packages/manifest.json" -Encoding utf8
if (-not (Test-Path -LiteralPath "$project/ProjectSettings/ProjectVersion.txt")) {
    'm_EditorVersion: 6000.3.20f1' | Set-Content -LiteralPath "$project/ProjectSettings/ProjectVersion.txt" -Encoding utf8
}
$exe = Join-Path $scratch 'build/Verification.exe'
$buildLog = Join-Path $scratch 'build.log'
if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe }
$process = Start-Process -FilePath $UnityEditor -WindowStyle Hidden -ArgumentList @('-batchmode','-nographics','-quit','-projectPath',('"'+$project+'"'),'-executeMethod','BuildVerification.Build','-player-output',('"'+$exe+'"'),'-logFile',('"'+$buildLog+'"')) -PassThru
$process.WaitForExit()
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'IL2CPP ビルド失敗。build.log を確認してください。' }
'PASS Windows x64 IL2CPP build'
function Invoke-PlayerCheck([string]$name, [bool]$fallback) {
    $result = Join-Path $scratch "player-$name-result.txt"
    if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result }
    $arguments = @('-batchmode','-nographics','-result',('"'+$result+'"'),'-logFile',('"'+(Join-Path $scratch "player-$name.log")+'"'))
    if ($fallback) { $arguments += '-expect-fallback' }
    $player = Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList $arguments -PassThru
    $player.WaitForExit()
    if ($player.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $result)) { throw "Player 検証失敗: $name" }
    $text = (Get-Content -LiteralPath $result -Raw).Trim()
    if ($text -notmatch '^PASS assertions=\d+ fallback=(True|False)$' -or ($Matches[1] -eq 'True') -ne $fallback) { throw "Player 結果が不正: $name" }
    "$name $text"
}
Invoke-PlayerCheck 'normal' $false
$exeHash = (Get-FileHash -LiteralPath $exe).Hash
foreach ($terminal in @($false, $true)) {
    $log = Join-Path $scratch "player-invalid-result-$terminal.log"
    $arguments = @('-batchmode','-nographics','-logFile',('"'+$log+'"'))
    if ($terminal) { $arguments += '-result' }
    $player = Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList $arguments -PassThru
    $player.WaitForExit()
    if ($player.ExitCode -ne 1 -or (Get-Content -LiteralPath $log -Raw) -notmatch 'ArgumentException: -result' -or
        (Get-FileHash -LiteralPath $exe).Hash -ne $exeHash) { throw '不正な結果引数の拒否に失敗しました。' }
}
'PASS 結果引数の欠落2ケースと実行ファイルの不変性'
$faultBuild = Join-Path $scratch 'runtime-fault-build'
& $CMake -S $fixtures -B $faultBuild -A x64 "-DREPO_ROOT=$repository" "-DGAMEINPUT_SDK=$SdkPath" *> "$scratch/fault-configure.log"
if ($LASTEXITCODE -ne 0) { throw '生成失敗 fixture の CMake 構成失敗。' }
& $CMake --build $faultBuild --config Release *> "$scratch/fault-build.log"
if ($LASTEXITCODE -ne 0) { throw '生成失敗 fixture のビルド失敗。' }
$dll = Join-Path $scratch 'build/Verification_Data/Plugins/x86_64/XbControllerNative.dll'
$backup = Join-Path $scratch 'original-native.dll'
Copy-Item -LiteralPath $dll -Destination $backup -Force
try {
    Copy-Item -LiteralPath "$faultBuild/Release/XbControllerNative.dll" -Destination $dll -Force
    Invoke-PlayerCheck 'runtime-fault' $true
    Remove-Item -LiteralPath $dll
    Invoke-PlayerCheck 'dll-missing' $true
} finally { Copy-Item -LiteralPath $backup -Destination $dll -Force }
if ((Get-FileHash -LiteralPath $dll).Hash -ne (Get-FileHash -LiteralPath "$repository/Runtime/Plugins/x86_64/XbControllerNative.dll").Hash) { throw 'Player DLL の復元が不正です。' }
'PASS 配布 DLL の復元'
