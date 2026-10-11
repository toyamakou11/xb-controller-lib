# 地面サンプルと #12 の実コードを合成実行する。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-RumbleSample.ps1'), [ref]$tokens, [ref]$errors)
$fixture = $ast.Find({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.StringConstantType -eq 'SingleQuotedHereString' }, $true).Value
$checks = @'
namespace UnityEngine {
    public static class Mathf { public static float Clamp01(float value) => Math.Max(0, Math.Min(1, value)); }
}
public static class GroundRumbleVerification {
    private static int assertions;
    private static void Check(bool value, string message) { assertions++; if (!value) throw new Exception(message); }
    private static void Invoke(object target, string method) {
        target.GetType().GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, null);
    }
    private static bool Output(Controller pad, float low, float high, float left, float right) {
        var expected = new[] { low, high, left, right };
        for (int i = 0; i < 4; i++) if (Math.Abs(pad.Output[i] - expected[i]) > 0.0001f) return false;
        return true;
    }
    public static int Run() {
        XboxControllers.All.Clear();
        XboxControllers.HasFocus = true;
        Time.unscaledTimeAsDouble = 100;
        var pad = new Controller();
        XboxControllers.All.Add(pad);
        var helper = new RumbleExample();
        var ground = new GroundRumbleExample { rumble = helper };
        Check(ground.ApplyGround(true, 3, GroundSurface.Smooth), "接地と速度を受け付ける");
        Check(Output(pad, 0.05f, 0.025f, 0.0125f, 0.0125f), "滑らかな地面と速度3の強度");
        ground.ApplyGround(true, 3, GroundSurface.Rough);
        Check(Output(pad, 0.2f, 0.1f, 0.05f, 0.05f), "粗い地面で強度を変える");
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        Check(Output(pad, 0.4f, 0.2f, 0.1f, 0.1f), "速度6で最大強度");
        ground.ApplyGround(true, 60, GroundSurface.Rough);
        Check(Output(pad, 0.4f, 0.2f, 0.1f, 0.1f), "速度の増加を最大強度で制限する");
        pad.SupportedRumbleMotors = 3;
        Check(ground.ApplyGround(true, 6, GroundSurface.Rough), "本体2モーター経路を受け付ける");
        Check(Output(pad, 0.4f, 0.2f, 0, 0), "非対応トリガーを要求しない");
        pad.SupportedRumbleMotors = 4;
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        Check(Output(pad, 0, 0, 0.1f, 0), "左トリガーだけの対応情報も使う");
        pad.SupportedRumbleMotors = 15;
        foreach (float speed in new[] { 0f, -1f, float.NaN, float.PositiveInfinity }) {
            ground.ApplyGround(true, 6, GroundSurface.Rough);
            Check(!ground.ApplyGround(true, speed, GroundSurface.Rough) && Output(pad, 0, 0, 0, 0), "停止と無効な速度で出力を停止する");
        }
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        Check(!ground.ApplyGround(false, 6, GroundSurface.Rough) && Output(pad, 0, 0, 0, 0), "接地解除で停止する");
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        pad.SupportedRumbleMotors = 0;
        Check(!ground.ApplyGround(true, 6, GroundSurface.Rough) && Output(pad, 0, 0, 0, 0), "対応モーターがないと停止する");
        pad.SupportedRumbleMotors = 15;
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        Time.unscaledTimeAsDouble = 100.05;
        ground.ApplyGround(true, 3, GroundSurface.Smooth);
        Time.unscaledTimeAsDouble = 100.11;
        Invoke(helper, "Update");
        Check(Output(pad, 0.05f, 0.025f, 0.0125f, 0.0125f), "更新で要求と期限を置き換える");
        Time.unscaledTimeAsDouble = 100.16;
        Invoke(helper, "Update");
        Check(Output(pad, 0, 0, 0, 0), "ゲームの更新が止まっても期限で停止する");
        foreach (string method in new[] { "OnDisable", "OnApplicationQuit" }) {
            ground.ApplyGround(true, 6, GroundSurface.Rough);
            Invoke(ground, method);
            Check(Output(pad, 0, 0, 0, 0), "無効化と終了で停止する");
        }
        ground.isActiveAndEnabled = false;
        Check(!ground.ApplyGround(true, 6, GroundSurface.Rough), "無効化中は開始しない");
        ground.isActiveAndEnabled = true;
        var replacement = new RumbleExample();
        ground.ApplyGround(true, 6, GroundSurface.Rough);
        ground.rumble = replacement;
        Check(ground.ApplyGround(true, 6, GroundSurface.Rough) && Output(pad, 0.4f, 0.2f, 0.1f, 0.1f), "制御例の変更時は以前の出力を先に停止する");
        ground.Stop();
        Check(Output(pad, 0, 0, 0, 0), "明示停止で出力を止める");
        int calls = pad.Calls.Count;
        ground.Stop();
        Check(pad.Calls.Count == calls, "所有していない出力を停止しない");
        ground.rumble = null;
        Check(!ground.ApplyGround(true, 6, GroundSurface.Rough), "制御例がないと拒否する");
        ground.rumble = helper;
        XboxControllers.All.Clear();
        Check(!ground.ApplyGround(true, 6, GroundSurface.Rough), "未接続では開始しない");
        XboxControllers.All.Add(pad);
        XboxControllers.HasFocus = false;
        Check(!ground.ApplyGround(true, 6, GroundSurface.Rough), "フォーカス喪失時は拒否する");
        return assertions;
    }
}
'@
$sources = foreach ($path in @('Samples~/Rumble/RumbleExample.cs', 'Samples~/GroundRumble/GroundRumbleExample.cs')) {
    (Get-Content -LiteralPath (Join-Path $repository $path) -Raw -Encoding utf8).Replace('using UnityEngine;', '').Replace('using XbController;', '')
}
Add-Type -TypeDefinition ($fixture + "`n" + $checks + "`n" + ($sources -join "`n"))
'PASS 基礎振動 assertions=' + [RumbleSampleVerification]::Run()
'PASS 地面振動 assertions=' + [GroundRumbleVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (@($package.samples | Where-Object path -eq 'Samples~/GroundRumble').Count -ne 1 -or
    -not (Test-Path -LiteralPath (Join-Path $repository 'Samples~/GroundRumble/README.md'))) { throw 'サンプル登録または手順がありません。' }
'PASS サンプル登録と操作手順'
