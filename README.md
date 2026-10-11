# Xbox Controller Library

Unity の標準コントローラー入力と振動を共通 API で扱う UPM ラッパーです。Unity Input System と Microsoft GameInput を再利用します。Input Actions の手動作成は不要です。

Elite Series 2 のパドルは、Xbox Accessories で割り当てた A/B/X/Y などの通常入力として扱います。プロファイルを変更しません。

Xbox Wireless Adapter は対応・検証対象外です。

## 導入

Unity 6000.3 以降の Package Manager で「Install package from git URL」を選びます。

```text
https://github.com/toyamakou11/xb-controller-lib.git#main
```

Input System 1.19.0 は依存として導入されます。旧 Input Manager のみの Editor は Active Input Handling を Both に設定し、再起動を案内します。既存の New/Both 設定と Actions は保持します。

Windows x64 は GameInput を既定にして、対応する4モーター振動と入力履歴を利用します。SDK 3.5.283 でビルドした DLL を同梱しています。GameInput v3 runtime がない場合や他 OS では、Unity Gamepad で標準入力と本体2モーター振動を扱います。

Microsoft runtime は自動インストールしません。GameInput を使う場合は公式 [NuGet パッケージ](https://www.nuget.org/packages/Microsoft.GameInput/3.5.283) の `redist/GameInputRedist.msi` を利用します。

## 最小例

```csharp
using UnityEngine;
using XbController;

public sealed class PlayerInputExample : MonoBehaviour
{
    private void Update()
    {
        var pads = XboxControllers.All;
        for (int i = 0; i < pads.Count; i++)
        {
            var pad = pads[i];
            Vector2 movement = pad.LeftStick;
            if (pad.WasPressed(XboxButton.A)) Debug.Log("A を押しました");
        }
    }
}
```

`Tools → Xbox Controller → 入力診断` で接続、ボタン、軸、診断値を確認できます。Package Manager のサンプル「入力確認」も利用可能です。

サンプル「標準入力のゲーム操作」は移動、視点、ボタン、LB/RB、LT/RT を示します。[導入と操作](Samples~/StandardInput/README.md) を参照してください。

サンプル「モーター別の振動」は個別、同時、時間指定の要求と停止を示します。[導入と操作](Samples~/Rumble/README.md) を参照してください。

サンプル「地面の振動」はゲーム側の接地と移動速度を振動へ接続します。[導入と停止規則](Samples~/GroundRumble/README.md) を参照してください。

サンプル「ゲームイベントの振動」は発射、反動、被弾を振動へ接続します。[導入と重なりの規則](Samples~/EventRumble/README.md) を参照してください。

## API

| API | 内容 |
| --- | --- |
| `XboxControllers.All` | 接続中の Gamepad の読み取り専用一覧。メインスレッド専用 |
| `Backend / BackendError / ShutdownError` | 使用経路と HRESULT 診断 |
| `Supports / SupportedButtons` | バックエンドが公開する対応情報 |
| `IsPressed / WasPressed / WasReleased` | 現在値、押下、解放 |
| `LeftStick / RightStick / Dpad / LeftTrigger / RightTrigger` | 軸。スティックは Input System のデッドゾーンを使用 |
| `SetRumble(low, high, leftTrigger, rightTrigger)` | 本体低/高周波と左右 impulse trigger への要求 |
| `SupportedRumbleMotors` | 低周波=1、高周波=2、左trigger=4、右trigger=8 |
| `ConnectionId / IsConnected / LastReadError` | 接続単位の識別と状態 |

振動値は有限値を0〜1に制限します。非対応モーターへの正の要求は拒否します。`SetRumble=true` は要求の受付を示し、物理応答を保証しません。ライブラリが開始した振動は、フォーカス喪失・切断・致命的な読み取り失敗・終了で停止します。

入力エッジは Input System の Dynamic/Fixed/Manual 更新に従います。GameInput は同じ更新内の短い押下と解放も蓄積します。履歴失効時は最新状態へ同期し、失われたエッジを作りません。古い Controller 参照は切断・無効化・再初期化後に中立値を返します。

Unity 経路を明示選択する場合は、ゲーム処理を始める前に `XboxControllers.Shutdown(); XboxControllers.Initialize(ControllerBackend.UnityInputSystem);` を呼びます。通常は初期化不要です。別の PlayerInput と同じ操作を重ねて処理しないでください。

Guide/Share はバックエンドと OS が公開する範囲に限ります。Profile/Pair はゲーム入力にしません。ゲームの移動・UI・プレイヤー割当は利用側で接続します。

## 0.2.0 の変更

独立パドル取得、GATT 補完、raw report 診断、パドル専用 API を削除しました。`PaddleLeft1/Left2/Right1/Right2/Paddles` の利用箇所は、実際の割当先ボタンへ変更してください。標準ボタンの値、振動 API、native ABI v1・80 bytesは保持します。

## 開発と対応範囲

```powershell
pwsh -NoProfile -File Tools/Build-Native.ps1
pwsh -NoProfile -File Tools/Test-NativePolling.ps1
pwsh -NoProfile -File Tools/Test-MultipleControllers.ps1
pwsh -NoProfile -File Tools/Test-Unity.ps1 -UnityEditor '<Unity Editor の絶対パス>'
pwsh -NoProfile -File Tools/Probe-Controller.ps1
pwsh -NoProfile -File Tools/Test-Rumble.ps1
```

標準 Gamepad として認識される端末を扱います。全機種・全接続の実機保証ではありません。USB-C の4モーター応答と停止は以前の実機試験で確認しました。現在の検証範囲は [検証記録](docs/verification.md)、契約は [設計](docs/design.md) を参照してください。

GitHub Actions は使用しません。ライセンスは [GPL-3.0-only](LICENSE)、Microsoft ローダーの表示は [第三者表記](THIRD_PARTY_NOTICES.md) にあります。
