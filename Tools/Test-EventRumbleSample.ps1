# イベントサンプルと #12 の実コードを合成実行する。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-RumbleSample.ps1'), [ref]$tokens, [ref]$errors)
$fixture = $ast.Find({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.StringConstantType -eq 'SingleQuotedHereString' }, $true).Value
$checks = @'
public static class EventRumbleVerification {
    private static int assertions;
    private static void Check(bool value, string message) { assertions++; if (!value) throw new Exception(message); }
    private static void Invoke(object target, string method, params object[] args) {
        target.GetType().GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, args);
    }
    private static bool Output(Controller pad, float low, float high, float left, float right) {
        var expected = new[] { low, high, left, right };
        for (int i = 0; i < 4; i++) if (Math.Abs(pad.Output[i] - expected[i]) > 0.0001f) return false;
        return true;
    }
    private static void Click(EventRumbleExample sample, string label) {
        GUILayout.Click = label;
        Invoke(sample, "OnGUI");
        Check(GUILayout.Click == null, "画面イベントが要求を処理する");
    }
    public static int Run() {
        XboxControllers.All.Clear();
        XboxControllers.HasFocus = true;
        var pad = new Controller();
        XboxControllers.All.Add(pad);
        var helper = new RumbleExample();
        var sample = new EventRumbleExample { rumble = helper };
        var labels = new[] { "発射", "反動", "被弾" };
        var outputs = new[] { new[] { 0.1f, 0.15f, 0f, 0.4f }, new[] { 0.3f, 0.2f, 0f, 0.6f }, new[] { 0.7f, 0.4f, 0.3f, 0.3f } };
        var seconds = new[] { 0.08f, 0.15f, 0.35f };
        for (int i = 0; i < labels.Length; i++) {
            Time.unscaledTimeAsDouble = 100;
            Click(sample, labels[i]);
            Check(Output(pad, outputs[i][0], outputs[i][1], outputs[i][2], outputs[i][3]), "イベント別の強度を使う");
            Time.unscaledTimeAsDouble = 100 + seconds[i] - 0.001;
            Invoke(helper, "Update");
            Check(Output(pad, outputs[i][0], outputs[i][1], outputs[i][2], outputs[i][3]), "イベントの期限前は保持する");
            Time.unscaledTimeAsDouble = 100 + seconds[i] + 0.001;
            Invoke(helper, "Update");
            Check(Output(pad, 0, 0, 0, 0), "イベント別の時間で停止する");
        }
        Time.unscaledTimeAsDouble = 200;
        Check(sample.Fire() && sample.Recoil(), "同じフレームの複数イベントを受け付ける");
        Check(Output(pad, 0.3f, 0.2f, 0, 0.6f), "合算せず最後のイベントを使う");
        Time.unscaledTimeAsDouble = 200.09;
        Invoke(helper, "Update");
        Check(Output(pad, 0.3f, 0.2f, 0, 0.6f), "古いイベントの期限では停止しない");
        Time.unscaledTimeAsDouble = 200.16;
        Invoke(helper, "Update");
        Check(Output(pad, 0, 0, 0, 0), "最後のイベントの期限で停止する");
        Time.unscaledTimeAsDouble = 300;
        sample.Hit();
        Time.unscaledTimeAsDouble = 300.01;
        sample.Fire();
        Check(Output(pad, 0.1f, 0.15f, 0, 0.4f), "被弾も後の発射で置き換える");
        Time.unscaledTimeAsDouble = 300.1;
        Invoke(helper, "Update");
        Check(Output(pad, 0, 0, 0, 0), "短い効果の期限へ置き換える");

        Time.unscaledTimeAsDouble = 400;
        sample.Fire();
        pad.AcceptRequests = false;
        Check(!sample.Hit() && Output(pad, 0.1f, 0.15f, 0, 0.4f), "API拒否で既存出力を保持する");
        pad.AcceptRequests = true;
        Time.unscaledTimeAsDouble = 400.09;
        Invoke(helper, "Update");
        Check(Output(pad, 0, 0, 0, 0), "API拒否で既存期限を変えない");
        pad.SupportedRumbleMotors = 3;
        Check(sample.Hit() && Output(pad, 0.7f, 0.4f, 0, 0), "本体2モーターへ制限する");
        pad.SupportedRumbleMotors = 8;
        Check(sample.Recoil() && Output(pad, 0, 0, 0, 0.6f), "右トリガーだけを使える");
        pad.SupportedRumbleMotors = 4;
        Check(sample.Hit() && Output(pad, 0, 0, 0.3f, 0), "左トリガーだけを使える");
        Check(!sample.Fire() && Output(pad, 0, 0, 0.3f, 0), "要求モーターが全て非対応なら拒否する");
        pad.SupportedRumbleMotors = 0;
        Check(!sample.Hit(), "対応モーターがないと拒否する");
        pad.SupportedRumbleMotors = 15;
        foreach (string method in new[] { "OnDisable", "OnApplicationQuit" }) {
            sample.Hit();
            Invoke(sample, method);
            Check(Output(pad, 0, 0, 0, 0), "無効化と終了で停止する");
        }
        sample.Fire();
        Click(sample, "効果を停止");
        Check(Output(pad, 0, 0, 0, 0), "画面から停止する");
        int calls = pad.Calls.Count;
        sample.Stop();
        Check(pad.Calls.Count == calls, "所有していない出力を停止しない");
        sample.Fire();
        sample.rumble = new RumbleExample();
        Check(sample.Hit() && Output(pad, 0.7f, 0.4f, 0.3f, 0.3f), "制御例の変更で新しい出力を残す");
        sample.Stop();
        sample.rumble = helper;
        sample.Fire();
        Invoke(helper, "OnApplicationFocus", false);
        XboxControllers.HasFocus = false;
        Check(!sample.Hit() && Output(pad, 0, 0, 0, 0), "フォーカス喪失で停止し新規要求を拒否する");
        XboxControllers.HasFocus = true;
        calls = pad.Calls.Count;
        Invoke(helper, "OnApplicationFocus", true);
        Invoke(helper, "Update");
        Check(pad.Calls.Count == calls, "フォーカス復帰では再開しない");
        sample.Fire();
        pad.IsConnected = false;
        XboxControllers.All.Clear();
        Invoke(helper, "Update");
        var replacement = new Controller();
        XboxControllers.All.Add(replacement);
        Invoke(helper, "Update");
        Check(replacement.Calls.Count == 0, "再接続では再開しない");
        Check(sample.Hit() && Output(replacement, 0.7f, 0.4f, 0.3f, 0.3f), "新しいイベントなら新しい接続を使う");
        sample.Stop();
        sample.isActiveAndEnabled = false;
        Check(!sample.Fire(), "無効化中は拒否する");
        sample.isActiveAndEnabled = true;
        sample.rumble = null;
        Check(!sample.Fire(), "制御例がないと拒否する");
        sample.rumble = helper;
        XboxControllers.All.Clear();
        Check(!sample.Fire(), "未接続では拒否する");
        return assertions;
    }
}
'@
$sources = foreach ($path in @('Samples~/Rumble/RumbleExample.cs', 'Samples~/EventRumble/EventRumbleExample.cs')) {
    (Get-Content -LiteralPath (Join-Path $repository $path) -Raw -Encoding utf8).Replace('using UnityEngine;', '').Replace('using XbController;', '')
}
Add-Type -TypeDefinition ($fixture + "`n" + $checks + "`n" + ($sources -join "`n"))
'PASS 基礎振動 assertions=' + [RumbleSampleVerification]::Run()
'PASS イベント振動 assertions=' + [EventRumbleVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (@($package.samples | Where-Object path -eq 'Samples~/EventRumble').Count -ne 1 -or
    -not (Test-Path -LiteralPath (Join-Path $repository 'Samples~/EventRumble/README.md'))) { throw 'サンプル登録または手順がありません。' }
'PASS サンプル登録と操作手順'
