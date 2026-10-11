# 参加サンプルと実 Controller を合成状態で実行する。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-MultipleControllers.ps1'), [ref]$tokens, [ref]$errors)
$fixture = $ast.Find({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.StringConstantType -eq 'SingleQuotedHereString' }, $true).Value
$checks = @'
namespace UnityEngine {
    public sealed class MinAttribute : Attribute { public MinAttribute(float value) {} }
    public enum Space { Self, World }
    public struct Vector3 {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public static Vector3 operator *(Vector3 value, float scale) => new Vector3(value.x*scale, value.y*scale, value.z*scale);
    }
    public class Transform {
        public Vector3 position;
        public void Translate(Vector3 offset, Space space) { position.x += offset.x; position.y += offset.y; position.z += offset.z; }
    }
    public class MonoBehaviour {}
    public static class Time { public static float deltaTime = 0.5f; }
    public static class Debug { public static readonly List<string> Logs = new List<string>(); public static void Log(object value) { Logs.Add(value.ToString()); } }
}
namespace XbController {
    public static class PlayerJoinVerification {
        private static int assertions;
        private static readonly MethodInfo poll = typeof(XboxControllers).GetMethod("PollNative", BindingFlags.NonPublic | BindingFlags.Static);
        private static void Check(bool value, string message) { assertions++; if (!value) throw new Exception(message); }
        private static bool Near(float actual, float expected) => Math.Abs(actual - expected) < 0.0001f;
        private static void Invoke(PlayerJoinExample sample, string method) {
            typeof(PlayerJoinExample).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance).Invoke(sample, null);
        }
        private static void Tick(PlayerJoinExample sample, params NativeSnapshot[] states) {
            NativeApi.Devices = states;
            poll.Invoke(null, null);
            Invoke(sample, "Update");
        }
        private static NativeSnapshot State(ulong token, float x, float y) {
            return new NativeSnapshot { Token = token, Supported = (ulong)(XboxButton.A | XboxButton.B), Buttons = (ulong)XboxButton.A, LeftX = x, LeftY = y };
        }
        public static int Run() {
            Debug.Logs.Clear();
            var one = State(101, 0.4f, 0);
            var two = State(202, 0, -0.6f);
            NativeApi.Devices = new[] { one, two };
            XboxControllers.Initialize();
            var sample = new PlayerJoinExample { players = new[] { new Transform(), new Transform() } };
            Invoke(sample, "OnEnable");
            Invoke(sample, "Update");
            Check(sample.GetController(0) == null && sample.GetController(1) == null, "A保持だけでは参加しない");
            one.Pressed = two.Pressed = (ulong)XboxButton.A;
            Tick(sample, one, two);
            var first = sample.GetController(0);
            var second = sample.GetController(1);
            Check(first != null && second != null && first.ConnectionId == 101 && second.ConnectionId == 202, "2台を別のプレイヤーへ割り当てる");
            Check(Debug.Logs.Count == 2 && Debug.Logs[0] == "プレイヤー 1: 参加" && Debug.Logs[1] == "プレイヤー 2: 参加", "接続tokenではなくスロット番号を表示する");
            Check(Near(sample.players[0].position.x, 0.6f) && Near(sample.players[0].position.z, 0), "プレイヤー1の入力で移動する");
            Check(Near(sample.players[1].position.x, 0) && Near(sample.players[1].position.z, -0.9f), "プレイヤー2の入力で移動する");
            Invoke(sample, "Update");
            Check(Debug.Logs.Count == 2 && ReferenceEquals(first, sample.GetController(0)) && ReferenceEquals(second, sample.GetController(1)), "同じedgeで重複参加しない");
            one.Pressed = two.Pressed = 0;
            one.LeftX = one.LeftY = two.LeftX = two.LeftY = 0;
            Tick(sample, one, two);
            Check(Debug.Logs.Count == 2, "Aの保持で再参加しない");
            var third = State(303, 1, 1);
            third.Pressed = (ulong)XboxButton.A;
            Tick(sample, one, two, third);
            Check(Debug.Logs.Count == 2 && ReferenceEquals(first, sample.GetController(0)) && ReferenceEquals(second, sample.GetController(1)), "満員では別の接続へ置き換えない");
            third.Pressed = 0;
            one.Buttons = one.Pressed = (ulong)XboxButton.B;
            Tick(sample, one, two, third);
            Check(Debug.Logs.Count == 3 && Debug.Logs[2] == "プレイヤー 1: B", "Bの操作をプレイヤーごとに分離する");
            var beforeFirst = sample.players[0].position;
            var beforeSecond = sample.players[1].position;
            two.LeftX = 0.2f;
            Tick(sample, two, third);
            Check(sample.GetController(0) == null && ReferenceEquals(second, sample.GetController(1)), "切断したスロットだけを空ける");
            Check(!first.IsConnected && first.LeftStick.x == 0 && !first.IsPressed(XboxButton.B), "古い参照は中立値を返す");
            Check(Near(sample.players[0].position.x, beforeFirst.x) && Near(sample.players[0].position.z, beforeFirst.z), "切断したプレイヤーは移動しない");
            Check(Near(sample.players[1].position.x, beforeSecond.x + 0.3f), "他方のプレイヤーは更新を続ける");
            Check(Debug.Logs.Count == 3, "空きスロットへ保持中の装置を自動割当しない");
            two.LeftX = 0;
            var returned = State(404, 0, 0.5f);
            Tick(sample, two, third, returned);
            Check(sample.GetController(0) == null, "再接続後も新しいAの押下を待つ");
            returned.Pressed = (ulong)XboxButton.A;
            Tick(sample, two, third, returned);
            var rejoined = sample.GetController(0);
            Check(rejoined != null && rejoined.ConnectionId == 404 && !ReferenceEquals(first, rejoined), "再参加は新しい接続参照を使う");
            Check(ReferenceEquals(second, sample.GetController(1)), "再参加で他方の割当を変更しない");
            Check(Near(sample.players[0].position.z, beforeFirst.z + 0.75f), "再参加した装置の入力で移動する");
            returned.Pressed = 0; returned.LeftY = 0;
            Tick(sample, returned, two, third);
            Check(ReferenceEquals(rejoined, sample.GetController(0)) && ReferenceEquals(second, sample.GetController(1)), "列挙順序の変更で割当を変えない");
            returned.Buttons = returned.Pressed = two.Buttons = two.Pressed = (ulong)XboxButton.B;
            int logs = Debug.Logs.Count;
            Tick(sample, returned, two);
            Check(Debug.Logs.Count == logs + 2 && Debug.Logs[logs] == "プレイヤー 1: B" && Debug.Logs[logs+1] == "プレイヤー 2: B", "同時操作も各プレイヤーへ分離する");
            Check(sample.GetController(-1) == null && sample.GetController(2) == null, "範囲外のスロットは未割当を返す");
            Invoke(sample, "OnDisable");
            Check(sample.GetController(0) == null && sample.GetController(1) == null, "無効化で割当を解除する");
            returned.Pressed = two.Pressed = 0;
            Invoke(sample, "OnEnable");
            Tick(sample, returned, two);
            Check(sample.GetController(0) == null && sample.GetController(1) == null, "再有効化で自動参加しない");
            returned.Buttons = returned.Pressed = (ulong)XboxButton.A;
            Tick(sample, returned, two);
            sample.players = new[] { sample.players[0] };
            returned.Pressed = 0;
            Tick(sample, returned, two);
            Check(sample.GetController(0) == null && sample.GetController(1) == null, "要素数の変更で割当を解除する");
            sample.players = null;
            Invoke(sample, "Update");
            Check(sample.GetController(0) == null, "対象がなくても安全に更新する");
            XboxControllers.Shutdown();
            return assertions;
        }
    }
}
'@
$sources = foreach ($path in @('Runtime/Controller.cs', 'Runtime/XboxControllers.cs', 'Runtime/XboxButton.cs', 'Samples~/PlayerJoin/PlayerJoinExample.cs')) {
    [regex]::Replace((Get-Content -LiteralPath (Join-Path $repository $path) -Raw -Encoding utf8), '(?m)^using [^\r\n]+;\r?\n', '')
}
$native = Get-Content -LiteralPath (Join-Path $repository 'Runtime/NativeApi.cs') -Raw -Encoding utf8
$snapshot = $native.Substring(0, $native.IndexOf('    internal static class NativeApi')) + "}`n"
$snapshot = $snapshot.Replace('using System.Runtime.InteropServices;', '')
Add-Type -TypeDefinition ("using System.Runtime.InteropServices;`nusing XbController;`n" + $fixture + "`n" + $checks + "`n" + ($sources -join "`n") + "`n" + $snapshot) -CompilerOptions '-define:UNITY_STANDALONE_WIN'
'PASS 基礎の2台合成 assertions=' + [XbController.MultipleControllerVerification]::Run()
'PASS 参加サンプル assertions=' + [XbController.PlayerJoinVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (@($package.samples | Where-Object path -eq 'Samples~/PlayerJoin').Count -ne 1 -or
    -not (Test-Path -LiteralPath (Join-Path $repository 'Samples~/PlayerJoin/README.md'))) { throw 'サンプル登録または手順がありません。' }
'PASS サンプル登録と操作手順'
