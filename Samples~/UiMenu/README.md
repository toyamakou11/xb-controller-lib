# コントローラーで UI メニューを操作する例

## 導入

1. Package Manager から「UI メニュー操作」を Import します。
2. EventSystem と Button を使う既存の UI を用意します。
3. 初期選択対象を EventSystem の Selected GameObject に設定します。
4. 空の GameObject に `ControllerMenuExample` を追加します。
5. 取消先の Button を `Cancel Button` に指定します。

Unity の `Selectable`、`EventSystem`、`Button` を使います。独自 UI は追加しません。

## 操作

| 入力 | 処理 |
| --- | --- |
| 十字キー | 選択を移動 |
| 左スティック | 閾値を超えた軸で選択を移動 |
| A | 選択中の UI 要素を決定 |
| B | 指定した取消 Button を実行 |

方向入力は押下時に1回移動します。長押しでは初期遅延後に一定間隔で移動します。十字キーとスティックが同時に入ると十字キーを使います。既定の EventSystem 方向・決定イベントを一時停止するため、同じ Gamepad 入力を二重処理しません。マウス入力は引き続き使えます。最初の接続コントローラーを使います。

## 検証範囲

`Tools/Test-UiMenuSample.ps1` はサンプルの実コードを合成入力で実行します。選択移動、初期遅延と繰り返し、入力の優先順位、決定・取消、EventSystem 設定の復元を確認します。Unity 参照コンパイルは API 互換性を確認します。Unity Play、実機入力、実 UI の表示は別の未検証条件です。
