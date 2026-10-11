# 地面の振動

ゲーム側の接地、実際の移動速度、地面の種類を振動へ接続します。地面判定はライブラリに追加しません。

## 導入

1. Package Manager で「モーター別の振動」を Import します。
2. 「地面の振動」を Import します。
3. GameObject に `RumbleExample` を追加します。
4. 同じ GameObject に `GroundRumbleExample` を追加します。
5. `rumble` にその `RumbleExample` を割り当てます。
6. ゲームの更新処理から `ApplyGround` を呼びます。

```csharp
groundRumble.ApplyGround(isGrounded, actualMoveSpeed, GroundSurface.Rough);
```

`isGrounded` と `actualMoveSpeed` はゲーム側で求めます。速度の単位は Unity 単位/秒です。入力の要求速度ではなく、実際の移動速度を使います。

## 強度と停止

速度6で最大強度になります。速度3では半分です。滑らかな地面 `Smooth` は最大 `0.1`、粗い地面 `Rough` は最大 `0.4` です。本体低周波を基準に、高周波は半分、左右トリガーは4分の1を要求します。非対応モーターは要求しません。

#12 の `RumbleExample.Play` を使い、更新ごとに `0.1` 秒の要求を置き換えます。更新が止まった場合も、期限後の `RumbleExample.Update` で停止します。非スケール時間を使います。

停止、接地解除、無効な速度、非対応装置、API 拒否で、この例が開始した出力を停止します。`Stop()`、無効化、終了でも停止します。切断とフォーカス喪失は #12 の停止処理を使います。保存した地面情報から自動再開しません。再開にはゲーム側の新しい `ApplyGround` 呼び出しが必要です。

この例専用の `RumbleExample` を使ってください。画面の手動ボタンや別の効果と出力を共有しないでください。`ApplyGround=true` は API 受付を示します。物理応答を保証しません。

```powershell
pwsh -NoProfile -File Tools/Test-GroundRumbleSample.ps1
```

合成実行と Unity 参照コンパイルで確認します。Unity Play、Import、画面表示、実機の振動と停止は別途確認が必要です。
