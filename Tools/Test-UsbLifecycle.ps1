[CmdletBinding()]
param([Parameter(Mandatory)][string]$UnityEditor, [switch]$BuildOnly)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $repository '.verification/issue7-physical'
$project = Join-Path ([IO.Path]::GetTempPath()) 'xb-controller-lib-physical-verification'
$inputPackage = Join-Path ([IO.Path]::GetTempPath()) 'xb-controller-lib-verification/inputsystem/package'
if (-not (Test-Path -LiteralPath "$inputPackage/package.json")) { throw '先に Tools/Test-Unity.ps1 を実行してください。' }
New-Item -ItemType Directory -Force "$scratch/build","$project/Assets/Player","$project/Assets/Editor","$project/Packages","$project/ProjectSettings" | Out-Null
Copy-Item -LiteralPath "$repository/Tests~/Physical/PhysicalVerification.cs" -Destination "$project/Assets/Player/PhysicalVerification.cs"
Copy-Item -LiteralPath "$repository/Tests~/Player/BuildVerification.cs" -Destination "$project/Assets/Editor/BuildVerification.cs"
'{"name":"XbController.Verification","references":["XbController.Runtime","Unity.InputSystem"]}' | Set-Content -LiteralPath "$project/Assets/Player/XbController.Verification.asmdef" -Encoding utf8
@{dependencies=@{
    'com.toyamakou11.xb-controller'='file:'+($repository -replace '\\','/')
    'com.unity.inputsystem'='file:'+($inputPackage -replace '\\','/')
    'com.unity.modules.imgui'='1.0.0'
}} | ConvertTo-Json | Set-Content -LiteralPath "$project/Packages/manifest.json" -Encoding utf8
if (-not (Test-Path -LiteralPath "$project/ProjectSettings/ProjectVersion.txt")) {
    'm_EditorVersion: 6000.3.20f1' | Set-Content -LiteralPath "$project/ProjectSettings/ProjectVersion.txt" -Encoding utf8
}
$exe = Join-Path $scratch 'build/Verification.exe'
if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe }
$process = Start-Process -FilePath $UnityEditor -WindowStyle Hidden -ArgumentList @('-batchmode','-nographics','-quit','-projectPath',('"'+$project+'"'),'-executeMethod','BuildVerification.Build','-player-output',('"'+$exe+'"'),'-logFile',('"'+(Join-Path $scratch 'build.log')+'"')) -PassThru
$process.WaitForExit()
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw '実機試験 Player のビルド失敗。' }
'PASS 実機試験 Player の IL2CPP ビルド'
if ($BuildOnly) { return }
$tag = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$evidence = Join-Path $scratch "evidence-usb-c-$tag.log"
$playerLog = Join-Path $scratch "player-usb-c-$tag.log"
$player = Start-Process -FilePath $exe -WindowStyle Normal -ArgumentList @('-screen-fullscreen','0','-screen-width','800','-screen-height','520','-evidence',('"'+$evidence+'"'),'-logFile',('"'+$playerLog+'"')) -PassThru
[pscustomobject]@{Pid=$player.Id;Evidence=$evidence;PlayerLog=$playerLog} | ConvertTo-Json | Set-Content -LiteralPath "$scratch/current-run.json" -Encoding utf8
"試験窓を表示しました。物理結果を記録してください。ログ: $evidence"
