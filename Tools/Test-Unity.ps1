# 専用の使い捨てプロジェクトで実 Unity Editor の検証を行う。
[CmdletBinding()]
param([Parameter(Mandatory)][string]$UnityEditor)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $repository '.verification') | Out-Null
$testRoot = Join-Path ([IO.Path]::GetTempPath()) 'xb-controller-lib-verification'
$project = Join-Path $testRoot 'unity'
$bundled = Join-Path (Split-Path -Parent $UnityEditor) 'Data/Resources/PackageManager/Editor/com.unity.inputsystem-1.19.0.tgz'
if (-not (Test-Path -LiteralPath $bundled)) { throw 'Input System 1.19.0 のバンドルがありません。' }
$inputPackage = Join-Path $testRoot 'inputsystem'
New-Item -ItemType Directory -Force $inputPackage,"$project/Assets/Verification","$project/Packages","$project/ProjectSettings" | Out-Null
& tar -xzf $bundled -C $inputPackage
if ($LASTEXITCODE -ne 0) { throw 'Input System 展開失敗' }
foreach ($name in @('Verification.cs','VerificationDriver.cs','XbController.Verification.asmdef')) {
    foreach ($suffix in @('', '.meta')) {
        $old = Join-Path "$project/Assets/Editor" ($name+$suffix)
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old }
    }
}
Copy-Item "$repository/Tests~/*" "$project/Assets/Verification" -Recurse -Force
$manifest = @{dependencies=@{
    'com.toyamakou11.xb-controller'='file:'+($repository -replace '\\','/')
    'com.unity.inputsystem'='file:'+("$inputPackage/package" -replace '\\','/')
    'com.unity.modules.imgui'='1.0.0'
    'com.unity.modules.uielements'='1.0.0'
}} | ConvertTo-Json
[IO.File]::WriteAllText("$project/Packages/manifest.json",$manifest)
if (-not (Test-Path "$project/ProjectSettings/ProjectVersion.txt")) {
    [IO.File]::WriteAllText("$project/ProjectSettings/ProjectVersion.txt","m_EditorVersion: 6000.3.20f1`n")
    [IO.File]::WriteAllText("$project/ProjectSettings/ProjectSettings.asset","%YAML 1.1`n%TAG !u! tag:unity3d.com,2011:`n--- !u!129 &1`nPlayerSettings:`n  m_ObjectHideFlags: 0`n  serializedVersion: 28`n  activeInputHandler: 2`n")
}
$resultFile = "$project/verification-result.txt"
if (Test-Path -LiteralPath $resultFile) { Remove-Item -LiteralPath $resultFile }
$process = Start-Process -FilePath $UnityEditor -WindowStyle Hidden -ArgumentList @('-batchmode','-nographics','-projectPath',('"'+$project+'"'),'-executeMethod','XbController.Verification.Verification.Start','-logFile',('"'+"$repository/.verification/unity-test.log"+'"')) -PassThru
# ライセンスサービス等の常駐子プロセスではなく Editor 本体の終了を待つ。
$process.WaitForExit()
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultFile)) { throw 'Unity 検証失敗。.verification/unity-test.log を確認してください。' }
$result = Get-Content -LiteralPath $resultFile -Raw
if ($result -notmatch '^PASS assertions=\d+') { throw 'Unity 検証が成功を報告していません。' }
$result.Trim()
