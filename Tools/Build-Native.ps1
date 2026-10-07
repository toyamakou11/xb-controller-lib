# 固定 SDK とローカル MSVC を使い Windows x64 DLL を再現可能にビルドする。
[CmdletBinding()]
param([string]$CMake, [string]$SdkPath)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $repository '.verification'
New-Item -ItemType Directory -Force $scratch | Out-Null
if (-not $CMake) {
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) { $CMake = $command.Source }
    else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (-not (Test-Path -LiteralPath $vswhere)) { throw 'CMake または Visual Studio C++ ツールが必要です。' }
        $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installation)) { throw 'Visual Studio C++ ツールが見つかりません。' }
        $CMake = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
        if (-not (Test-Path -LiteralPath $CMake -PathType Leaf)) { throw "CMake が見つかりません: $CMake" }
    }
}
if (-not $SdkPath) {
    $zip = Join-Path $scratch 'gameinput.zip'
    $expected = 'B5988CB8FF9D7009B6DDF6AD4E3FF87E91B00CC17FFCD5D628DABC21C208F100'
    if (-not (Test-Path -LiteralPath $zip)) {
        Invoke-WebRequest 'https://api.nuget.org/v3-flatcontainer/microsoft.gameinput/3.5.283/microsoft.gameinput.3.5.283.nupkg' -OutFile $zip
    }
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) { throw 'SDK の SHA-256 が一致しません。' }
    $SdkPath = Join-Path $scratch 'sdk'
    Expand-Archive -LiteralPath $zip -DestinationPath $SdkPath -Force
}
$build = Join-Path $scratch 'native-build'
& $CMake -S "$repository/Native" -B $build -A x64 "-DGAMEINPUT_SDK=$SdkPath" -DBUILD_TESTING=ON
if ($LASTEXITCODE -ne 0) { throw 'CMake 構成失敗' }
& $CMake --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'C++ ビルド失敗' }
& (Join-Path (Split-Path -Parent $CMake) 'ctest.exe') --test-dir $build -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'C++ 回帰テスト失敗' }
$output = Join-Path $repository 'Runtime/Plugins/x86_64'
New-Item -ItemType Directory -Force $output | Out-Null
Copy-Item "$build/Release/XbControllerNative.dll" "$output/XbControllerNative.dll" -Force
Get-FileHash "$output/XbControllerNative.dll" -Algorithm SHA256
