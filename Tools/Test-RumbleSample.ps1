# サンプル実コードの合成試験。API の代役は物理応答を示さない。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$fixture = @'
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;
using XbController;
namespace UnityEngine {
    public sealed class RangeAttribute : Attribute { public RangeAttribute(float min, float max) {} }
    public sealed class MinAttribute : Attribute { public MinAttribute(float min) {} }
    public class MonoBehaviour { public bool isActiveAndEnabled = true; }
    public static class Time { public static double unscaledTimeAsDouble; }
    public struct Rect { public Rect(float x, float y, float width, float height) {} }
    public class GUIStyle {}
    public class GUISkin { public GUIStyle box = new GUIStyle(); }
    public static class GUI { public static GUISkin skin = new GUISkin(); }
    public static class GUILayout {
        public static string Click;
        public static void BeginArea(Rect rect, GUIStyle style) {}
        public static void EndArea() {}
        public static void Label(string text) {}
        public static bool Button(string text) { if (Click != text) return false; Click = null; return true; }
    }
}
namespace XbController {
    public class Controller {
        public bool IsConnected = true, AcceptRequests = true;
        public uint SupportedRumbleMotors = 15;
        public readonly List<float[]> Calls = new List<float[]>();
        public float[] Output = new float[4];
        public bool SetRumble(float low, float high, float left, float right) {
            var values = new[] { low, high, left, right };
            Calls.Add(values);
            if (!IsConnected || !AcceptRequests || !XboxControllers.HasFocus) return false;
            for (int i = 0; i < 4; i++) {
                if (float.IsNaN(values[i]) || float.IsInfinity(values[i])) return false;
                values[i] = Math.Max(0, Math.Min(1, values[i]));
                if (values[i] > 0 && (SupportedRumbleMotors & (1u << i)) == 0) return false;
            }
            Output = values;
            return true;
        }
    }
    public static class XboxControllers {
        public static bool HasFocus = true;
        public static readonly List<Controller> All = new List<Controller>();
    }
}
public static class RumbleSampleVerification {
    private static int assertions;
    private static void Check(bool value, string message) { assertions++; if (!value) throw new Exception(message); }
    private static void Invoke(RumbleExample sample, string method, params object[] args) {
        typeof(RumbleExample).GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(sample, args);
    }
    private static RumbleExample Create(Controller pad) {
        XboxControllers.All.Clear();
        if (pad != null) XboxControllers.All.Add(pad);
        XboxControllers.HasFocus = true;
        Time.unscaledTimeAsDouble = 100;
        return new RumbleExample();
    }
    private static bool Output(Controller pad, float low, float high, float left, float right) {
        var expected = new[] { low, high, left, right };
        for (int i = 0; i < 4; i++) if (Math.Abs(pad.Output[i] - expected[i]) > 0.0001f) return false;
        return true;
    }
    private static void Click(RumbleExample sample, string label) {
        GUILayout.Click = label;
        Invoke(sample, "OnGUI");
        Check(GUILayout.Click == null, "画面ボタンが要求を処理する");
    }
    public static int Run() {
        var pad = new Controller();
        var sample = Create(pad);
        var labels = new[] { "本体低周波", "本体高周波", "左トリガー", "右トリガー" };
        for (int motor = 0; motor < 4; motor++) {
            Click(sample, labels[motor]);
            for (int i = 0; i < 4; i++) Check(pad.Output[i] == (i == motor ? 0.25f : 0), "指定モーターだけを要求する");
        }
        Click(sample, "対応モーターを同時に要求");
        Check(Output(pad, 0.25f, 0.25f, 0.25f, 0.25f), "4モーターを同時に要求する");
        Click(sample, "停止");
        Check(Output(pad, 0, 0, 0, 0), "手動で停止する");
        int calls = pad.Calls.Count;
        sample.Stop();
        Check(pad.Calls.Count == calls, "停止済みなら他の出力を触らない");
        pad.SupportedRumbleMotors = 3;
        Click(sample, "対応モーターを同時に要求");
        Check(Output(pad, 0.25f, 0.25f, 0, 0), "本体2モーターの経路を扱う");
        Click(sample, "左トリガー");
        Check(Output(pad, 0.25f, 0.25f, 0, 0), "非対応の個別要求で既存出力を保持する");
        Time.unscaledTimeAsDouble = 101;
        Invoke(sample, "Update");
        Check(Output(pad, 0, 0, 0, 0), "拒否された要求が既存の期限を延ばさない");

        sample = Create(pad);
        Check(sample.Play(0.4f, 0.2f, 0, 0, 2), "時間指定を受け付ける");
        Time.unscaledTimeAsDouble = 101.999;
        Invoke(sample, "Update");
        Check(Output(pad, 0.4f, 0.2f, 0, 0), "期限前は停止しない");
        Time.unscaledTimeAsDouble = 102;
        Invoke(sample, "Update");
        Check(Output(pad, 0, 0, 0, 0), "非スケール時間の期限で停止する");

        sample = Create(pad);
        sample.Play(0.3f, 0, 0, 0, 2);
        Time.unscaledTimeAsDouble = 101;
        Check(sample.Play(0, 0.5f, 0, 0, 3), "新しい要求を受け付ける");
        Time.unscaledTimeAsDouble = 102;
        Invoke(sample, "Update");
        Check(Output(pad, 0, 0.5f, 0, 0), "重ねずに出力と期限を置き換える");
        Time.unscaledTimeAsDouble = 104;
        Invoke(sample, "Update");
        Check(Output(pad, 0, 0, 0, 0), "置換後の期限で停止する");

        sample = Create(pad);
        sample.Play(0.3f, 0, 0, 0, 2);
        calls = pad.Calls.Count;
        foreach (float seconds in new[] { 0f, -1f, float.NaN, float.PositiveInfinity })
            Check(!sample.Play(0, 0.5f, 0, 0, seconds), "無効な時間を拒否する");
        Check(pad.Calls.Count == calls, "無効な時間ではAPIを呼ばない");
        Check(!sample.Play(float.NaN, 0, 0, 0, 10), "非有限の出力を拒否する");
        Check(!sample.Play(0, float.PositiveInfinity, 0, 0, 10), "無限の出力を拒否する");
        Check(Output(pad, 0.3f, 0, 0, 0), "拒否時は既存出力を保持する");
        pad.AcceptRequests = false;
        Check(!sample.Play(0, 0.5f, 0, 0, 10), "API失敗を返す");
        pad.AcceptRequests = true;
        Time.unscaledTimeAsDouble = 102;
        Invoke(sample, "Update");
        Check(Output(pad, 0, 0, 0, 0), "失敗時は元の期限を保持する");

        foreach (string method in new[] { "OnDisable", "OnApplicationQuit", "OnApplicationFocus" }) {
            sample = Create(pad);
            sample.Play(0.3f, 0, 0, 0, 10);
            if (method == "OnApplicationFocus") Invoke(sample, method, false);
            else Invoke(sample, method);
            Check(Output(pad, 0, 0, 0, 0), "寿命イベントで停止する");
            calls = pad.Calls.Count;
            if (method == "OnApplicationFocus") Invoke(sample, method, true);
            Invoke(sample, "Update");
            Check(pad.Calls.Count == calls, "有効化とフォーカス復帰で再開しない");
        }
        sample = Create(pad);
        sample.Play(0.3f, 0, 0, 0, 10);
        XboxControllers.HasFocus = false;
        Invoke(sample, "Update");
        XboxControllers.HasFocus = true;
        calls = pad.Calls.Count;
        Invoke(sample, "Update");
        Check(pad.Calls.Count == calls, "ライブラリのフォーカス喪失でも要求を破棄する");

        sample = Create(pad);
        sample.Play(0.3f, 0, 0, 0, 10);
        var second = new Controller();
        XboxControllers.All[0] = second;
        second.AcceptRequests = false;
        Check(!sample.Play(0, 0.5f, 0, 0, 2) && Output(pad, 0.3f, 0, 0, 0), "接続変更の失敗で以前の出力を保持する");
        second.AcceptRequests = true;
        Check(sample.Play(0, 0.5f, 0, 0, 2), "新しい接続へ要求する");
        Check(Output(pad, 0, 0, 0, 0) && Output(second, 0, 0.5f, 0, 0), "新しい接続の受付後に古い接続を停止する");
        second.IsConnected = false;
        XboxControllers.All.Clear();
        Invoke(sample, "Update");
        var replacement = new Controller();
        XboxControllers.All.Add(replacement);
        Invoke(sample, "Update");
        sample.Stop();
        Check(replacement.Calls.Count == 0, "切断と再接続で自動再開しない");

        sample = Create(null);
        Check(!sample.Play(1, 0, 0, 0, 1), "未接続では拒否する");
        sample = Create(pad);
        sample.isActiveAndEnabled = false;
        Check(!sample.Play(1, 0, 0, 0, 1), "無効化中は拒否する");
        sample.isActiveAndEnabled = true;
        XboxControllers.HasFocus = false;
        Check(!sample.Play(1, 0, 0, 0, 1), "フォーカスがないと拒否する");
        return assertions;
    }
}
'@
$source = Get-Content -LiteralPath (Join-Path $repository 'Samples~/Rumble/RumbleExample.cs') -Raw -Encoding utf8
Add-Type -TypeDefinition ($fixture + "`n" + $source.Replace('using UnityEngine;', '').Replace('using XbController;', ''))
'PASS assertions=' + [RumbleSampleVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
$sample = @($package.samples | Where-Object path -eq 'Samples~/Rumble')
if ($sample.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $repository ($sample[0].path + '/README.md')))) {
    throw 'サンプル登録または操作手順がありません。'
}
if (@($package.dependencies.PSObject.Properties).Count -ne 1 -or $package.dependencies.'com.unity.inputsystem' -ne '1.19.0') {
    throw '依存が変更されています。'
}
'PASS サンプル登録、操作手順、既存依存'
