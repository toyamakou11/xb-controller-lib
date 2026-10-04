# Xbox Controller Library

Unity に Git URL から追加する、Xbox の標準入力と Windows GameInput の独立パドル用 UPM ライブラリです。Input Actions の手動作成は不要です。

**現在の実機確認では独立4パドルは未達です。** API と対応情報の判定は実装していますが、手元の接続で公開されない物理入力を生成したり、ABXY から推測したりしません。詳細は [検証記録](docs/verification.md) を参照してください。

## 導入

Unity 6000.3 以降の Package Manager →「Install package from git URL」に次を指定します。PR の確認中はブランチ指定を使用してください。

```text
https://github.com/toyamakou11/xb-controller-lib.git#codex/xbox-input-paddles
```

Input System 1.19.0 は依存として導入されます。旧 Input Manager のみのプロジェクトでは初回 Editor 読み込み時に Active Input Handling を Both に変更し、Console に再起動の案内を出します。Input System/Both の既存設定は維持します。既存プロジェクトの Actions やシーンを作り替えることはありません。

Windows の独立入力には **x64 と GameInput 3.3 以降のランタイム**が必要です。同梱 DLL は SDK 3.5.283 でビルド済みです。Microsoft ランタイムは同梱・自動インストールせず、公式 [GameInput NuGet](https://www.nuget.org/packages/Microsoft.GameInput/3.5.283) の `redist/GameInputRedist.msi` を利用します。ランタイム不在・API 不一致時は標準入力へフォールバックし、エラーを表示します。

## 利用例

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
            if (pad.Supports(XboxButton.PaddleLeft1) && pad.WasPressed(XboxButton.PaddleLeft1))
                Debug.Log("左パドル1を押しました");
        }
    }
}
```

`Tools → Xbox Controller → 入力診断` で全ボタンの対応可否・現在値・エラーを確認できます。Package Manager のサンプル「入力確認」も利用可能です。

| API | 内容 |
| --- | --- |
| `XboxControllers.All` | 有効な全 Gamepad の読み取り専用ビュー。メインスレッド専用 |
| `Backend / BackendError / ShutdownError` | 使用バックエンドと HRESULT 診断 |
| `Supports / SupportedButtons` | 端末が公開する対応情報。未押下とは別 |
| `IsPressed / WasPressed / WasReleased` | 現在値と選択された Input System 更新単位のエッジ |
| `LeftStick / RightStick / Dpad / LeftTrigger / RightTrigger` | 正規化された軸。スティックは Input System 設定のデッドゾーン |
| `SetRumble(low, high, leftTrigger, rightTrigger)` | 本体低/高周波、左右 impulse trigger へ要求。有限値を0〜1に制限。true は送信受付であり実機応答の保証ではない |
| `SupportedRumbleMotors` | 公式能力bit: 低周波=1、高周波=2、左trigger=4、右trigger=8。Unity fallback は本体2モーターのみ |
| `ConnectionId / IsConnected / LastReadError` | 接続単位の識別・有効性・読み取り HRESULT |

Elite Series 2 Core の USB-C では、本体低/高周波と左右 impulse trigger の個別振動・停止をユーザー観測で確認しました（各0.25、700 ms）。無線接続や他機種の保証ではありません。[試験条件と未検証項目](docs/verification.md) を参照してください。

Windows は GameInput を主入力にし、他 OS や初期化失敗時は Unity の標準 Gamepad を使います。Xbox 360/One/Series/Elite を機種番号で決め打ちせず、バックエンドが公開する Gamepad を検出します。Xbox 以外でも Unity/GameInput の標準レイアウトとして認識される端末は対象になります。全機種・全接続を実機検証した意味ではありません。

## パドルとシステムボタン

4パドルの名前は `PaddleLeft1 / PaddleLeft2 / PaddleRight1 / PaddleRight2` です。`Supports(XboxButton.Paddles)` はバックエンドが4個すべての対応情報を公開した場合に true です。これは実際に物理パドルの値が届く保証ではありません。USB 実機では対応情報が true でも独立値が0のままでした。Xbox Accessories で A 等に割り当てた入力だけが見える場合、A とパドルの物理的な区別はできません。プロファイルは自動変更しません。

Elite Series 2 Core のトリガーロックやスティック張力調整は機械的な調整であり、追加キーではありません。Profile/Pair はこのライブラリのゲーム入力対象外です。Guide/Share は GameInput の system callback と対応情報が公開する場合に扱いますが、OS が消費する場合があります。Elite の Profile ボタンを Share と見なすことはありません。[Xbox 公式仕様](https://www.xbox.com/en-US/accessories/controllers/xbox-elite-wireless-controller-series-2-core)

## 更新と安定性

- 通常は初期化不要です。バックエンドを明示選択する場合、初回読み取り前に `XboxControllers.Initialize(ControllerBackend.UnityInputSystem)` を呼びます。途中切り替えは `Shutdown()` の後に再初期化します。
- 入力エッジは Dynamic/Fixed/Manual の選択された更新単位です。同じ更新内の短い押下と解放を GameInput 履歴から蓄積します。履歴失効時は最新値へ同期し、失われたエッジを推測しません。`LastReadError=0x838A0004` はこの再同期を示します。
- 切断・無効化・再初期化後の古い参照は中立値を返します。再接続時は新参照です。`ConnectionId` を永続的な機種IDやプレイヤー番号に使わないでください。
- フォーカス喪失・切断・nativeの致命的読み取り失敗・終了では、このライブラリが開始した振動を停止します。復帰後の自動振動再開はありません。出力は公開能力に従い、各接続での実機応答は別途試験が必要です。
- 接続列挙の安定性のため GameInput インスタンスは背景入力を許可しますが、ゲームへの読み取りは Unity のフォーカス状態で制限します。Editor の非 Play 診断では接続状態を表示します。
- Unity 自体の Gamepad は削除しません。同一ゲーム操作にこの API と別の XInput/PlayerInput を重ねると二重処理になるため、入力の呼び出し元を統一してください。

## 開発と検証

```powershell
# Visual Studio の C++ ツールと CMake が必要。SDK は固定 SHA-256 で確認する。
pwsh -NoProfile -File Tools/Build-Native.ps1

# 引数にインストール済み Unity Editor のパスを渡す。
pwsh -NoProfile -File Tools/Test-Unity.ps1 -UnityEditor '<Unity Editor の絶対パス>'

# プロファイルと振動を変更せず対応情報を確認する。
pwsh -NoProfile -File Tools/Probe-Controller.ps1

# 同一セッションで端末を明示選択し、モーター別の短い実機試験を行う。
pwsh -NoProfile -File Tools/Test-Rumble.ps1
```

設計と独立レビューへの対応は [設計文書](docs/design.md)、検証範囲は [検証記録](docs/verification.md) を参照してください。GitHub Actions は使用しません。ライセンスは既存の [GPL](LICENSE)、Microsoft ローダーの表示は [第三者表記](THIRD_PARTY_NOTICES.md) を参照してください。
