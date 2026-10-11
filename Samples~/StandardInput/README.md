# 標準入力のゲーム操作例

## 導入

1. Unity 6000.3 以降の Package Manager で「Install package from git URL」を選びます。
2. `https://github.com/toyamakou11/xb-controller-lib.git#main` を入力します。
3. パッケージの Samples から「標準入力のゲーム操作」を Import します。
4. 空の GameObject に `StandardInputExample` を追加します。
5. 子の Camera を `View` に指定します。Camera のローカル回転をゼロにします。

移動量は毎秒3単位、視点速度は毎秒120度です。Inspector で調整できます。この例は既定の Dynamic 更新を前提にします。最初の接続コントローラーを使います。切断後は一覧の先頭を使います。接続 ID をプレイヤー番号にしません。

## 操作

| 入力 | 処理 |
| --- | --- |
| 左スティック | 本体の向きに沿って水平移動 |
| 右スティック | 本体の左右回転と Camera の上下回転。上下は±80度 |
| A / B / X / Y | 操作 / 取消 / リロード / 切替のログ |
| LB / RB | 保持中は移動速度を半分 / 2倍。両方保持すると相殺 |
| LT | 押し込み量に応じて移動速度を最大半分にする |
| RT | 押下時に発射ログと強度を1回表示 |

重力、衝突、弾、リロード処理は実装しません。ログをゲーム側の処理へ置き換えます。同じ操作を別の `PlayerInput` でも処理しないでください。振動、独立パドル、機器設定の変更は行いません。追加の依存はありません。

## 検証範囲

`Tools/Test-StandardInputSample.ps1` はサンプルの実コードを合成入力で実行します。移動量、視点の制限、ボタン処理、切断後の停止を確認します。インストール済み Unity の参照コンパイルは API の互換性を確認します。Unity Play、実機操作、描画、Package Manager の Import 操作は別の未検証条件です。
