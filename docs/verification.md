# ローカル検証記録

## 現在の対象

0.2.0 の対象は標準入力と振動です。リマッピング済みパドルは A/B/X/Y などの通常入力として扱います。独立パドルの受信は合格条件に含めません。

Xbox Wireless Adapter は対応・検証対象外です。Issue #4 の実機検証は行わず、範囲変更として扱います。以前の USB-C と Bluetooth の実機成果は保持します。

## 2026年10月10日の整理

| 検査 | 結果 |
| --- | --- |
| C++17、Windows x64、SDK 3.5.283、MSVC /W4 /WX | ビルド成功 |
| native 合成回帰 | CTest 1/1 成功。標準入力、短い押下・解放、接続寿命、4モーター、終了再試行 |
| C# facade 合成回帰 | 10 assertions 成功。容量交渉、一覧、既存参照、失敗時の無効化 |
| Unity 6000.3.20f1 Play | license 不足で exit 198。Play 開始前に失敗 |
| 実 Unity 参照コンパイル | Runtime、Editor、検証、driver、sample の5 assemblyが C#9・警告をエラー扱いで成功 |
| 配布 DLL の受信専用 probe | 初期化、2 device の列挙・poll、終了でエラーなし。物理操作試験とは別 |

配布 DLL の SHA-256 は `C0FC194832DFF6423BEA4FC03485EF1AF51186EF83D8776CA9AB1FD89FFC8147` です。ABI v1・80 bytesを保持しました。GATT worker、独立ボタン mapper、raw report 診断、専用ツールを削除しました。

今回の合成入力は物理パドル由来を区別しません。割当先の通常 Gamepad state が公開 API に届くことを確認します。Unity Play の成功を参照コンパイルから推定しません。最初の sandbox 実行は一時フォルダーの書込権限で中断しました。通常環境での再実行は license 不足で終了しました。

## 2026年10月11日の標準入力と振動の実機確認

Xbox Elite Series 2 を USB-C で接続して確認しました。機種名はユーザーが確認しました。firmware version は取得できていません。

GameInput probe は1台を列挙し、callback 診断 `0x00000000` を返しました。最初の試行は押下・解放 `0x0000000003FF0FFD`、次の試行は `0x0000000003FF3D68` を記録しました。View の解放 edge `0x2` も別の試行で記録しました。標準ボタンの合算は `0x0000000003FF3FFF` です。両スティックは各軸で `-1.0` から `1.0`、左右トリガーは `0.0` から `1.0` を記録しました。

各モーターへ `0.25` を `700 ms` 要求しました。API の要求と停止は4モーターとも `0x00000000` でした。ユーザーは指定位置だけが振動し、要求後に停止したと確認しました。

これは配布 DLL の GameInput probe と実機観察です。Unity Play の検証ではありません。USB-C試験時点では、firmware version、Bluetooth、他機種、複数実機、IL2CPP Player、フォーカス喪失と切断時の停止は未検証でした。

## 2026年10月11日のBluetooth振動実機確認

GameInput は1台を列挙し、読み取りエラーと callback 診断は `0x00000000` でした。デバイス表示名は `Xbox Wireless Controller` です。モデルと firmware version は確認していません。

配布 DLL の `xb_rumble` に各モーター `0.25`、`700 ms` を要求しました。対応マスクは `0xF` でした。各要求と停止の HRESULT は `0x00000000` でした。

| 要求 | ユーザーが確認した位置 | 要求後 |
| --- | --- | --- |
| LowFrequency | 本体左のみ | 停止 |
| HighFrequency | 本体右のみ | 停止 |
| LeftTrigger | 左トリガーのみ | 停止 |
| RightTrigger | 右トリガーのみ | 停止 |

この試験は Bluetooth 接続でのネイティブ API 要求と物理応答です。Unity Play の結果ではありません。他機種、firmware、複数実機、IL2CPP Player、フォーカス喪失と切断時の停止は未検証です。

## 2026年10月11日の標準入力サンプル確認

Issue #10 の「標準入力のゲーム操作」を追加しました。公開 API で移動、視点、A/B/X/Y、LB/RB、LT/RT を扱います。既定の Dynamic 更新を前提にします。依存は Input System 1.19.0 のままです。

| 検査 | 結果と範囲 |
| --- | --- |
| サンプル実コードの合成実行 | 16 assertions 成功。方向と移動量、肩ボタン、LT、視点の制限、押下ログ、切断後の停止 |
| パッケージ情報 | サンプル登録、操作手順、既存依存を確認。Package Manager の Import 操作は未実施 |
| インストール済み Unity 6000.3.20f1 の参照コンパイル | Runtime、Editor、検証、driver、既存と新規サンプルの6 assemblyを C#9・警告をエラー扱いでコンパイル |
| C++17 Release ビルドと native 合成回帰 | CTest 1/1 成功。既存の native 入力と振動の回帰 |
| C# facade 合成回帰 | 10 assertions 成功。既存の poll と参照寿命の回帰 |

サンプルの実機操作、描画、Unity Play は未検証です。参照コンパイルと合成入力は、その代わりの実機証拠にしません。今回のサンプルは振動を要求しません。以前の USB-C と Bluetooth の実機成果は別の記録です。

## 2026年10月11日の UI メニューサンプル確認

Issue #16 の「UI メニュー操作」を追加しました。既存の `Selectable`、`EventSystem`、`Button` と公開入力 API を使います。十字キーとスティックで選択を動かし、A で決定し、B で指定した取消項目を実行します。

| 検査 | 結果と範囲 |
| --- | --- |
| サンプル実コードの合成実行 | 13 assertions 成功。選択、閾値、入力優先、長押し、連打、決定・取消、二重処理防止、設定復元 |
| パッケージ情報 | サンプル登録、操作手順、既存依存を確認。Package Manager の Import 操作は未実施 |
| Unity 6000.3.20f1 の参照コンパイル | 6サンプルを同時に C#9・警告をエラー扱いでコンパイル |

Unity Play、Package Manager の Import、実機入力と画面表示は未検証です。合成入力と参照コンパイルは実機結果を証明しません。

## 2026年10月11日の振動サンプル確認

Issue #12 の「モーター別の振動」を追加しました。公開 API で個別、同時、時間指定の要求を扱います。非対応要求は既存出力と期限を保持します。停止と接続変更の規則をサンプルに記載しました。

| 検査 | 結果と範囲 |
| --- | --- |
| サンプル実コードの合成実行 | 60 assertions 成功。4モーター、2モーター、期限、要求の置換と拒否、停止、切断と再接続 |
| 既存の合成回帰 | 標準入力サンプル16、facade10 assertions 成功 |
| インストール済み Unity 6000.3.20f1 の参照コンパイル | Runtime、Editor、検証、driver、3サンプルの7 assemblyを C#9・警告をエラー扱いでコンパイル |
| C++17 Release ビルドと native 合成回帰 | CTest 1/1 成功。配布 DLL の SHA-256 は上記の値を保持 |
| パッケージ情報 | サンプル登録、操作手順、Input System 1.19.0 の既存依存を確認 |

合成試験は実サンプルコードを使い、Unity と Controller を代役に置き換えます。API 受付は物理応答を証明しません。今回のネイティブ API 実機要求は未実施です。Unity Play、Import 操作、画面表示、実機の振動と停止は未検証です。USB-C と Bluetooth の以前の実機証拠は別の記録として保持しました。

## 2026年10月11日の地面振動サンプル確認

Issue #13 の「地面の振動」を追加しました。ゲーム側の接地、速度、地面の種類を #12 の制御例へ渡します。対応モーターだけを使い、停止と接地解除で所有出力を停止します。

| 検査 | 結果と範囲 |
| --- | --- |
| 実サンプルコードの合成実行 | 地面25、基礎振動60 assertions 成功。地面別・速度別の強度、対応情報、期限、停止、制御例の変更 |
| 既存回帰 | 標準入力16、facade10 assertions、native CTest 1/1 成功 |
| Unity 6000.3.20f1 参照コンパイル | 8 assembly 成功。C#9、警告をエラー扱い。基礎振動との参照も確認 |
| C++17 Release ビルド | 成功。配布 DLL の SHA-256 は上記の値を保持 |

Unity と Controller は合成試験の代役です。今回のネイティブ API 実機要求は未実施です。Unity Play、Import、画面表示、地面判定との実ゲーム統合、実機応答は未検証です。以前の USB-C と Bluetooth の証拠とは分けます。

## 2026年10月11日のイベント振動サンプル確認

Issue #14 の「ゲームイベントの振動」を追加しました。発射、反動、被弾の強度と時間を変えます。対応モーターへ制限し、最後に受け付けたイベントで出力と期限を置き換えます。

| 検査 | 結果と範囲 |
| --- | --- |
| 実サンプルコードの合成実行 | イベント38、基礎振動60 assertions 成功。強度、期限、重なり、拒否、停止、フォーカスと再接続 |
| 地面サンプル回帰 | 25 assertions 成功。サンプル登録と操作手順も確認 |
| Unity 6000.3.20f1 参照コンパイル | 個別9 assemblyと全5サンプルの結合1 assemblyが成功。C#9、警告をエラー扱い |
| 既存 native・facade・標準入力検査 | #13 で同日に成功した結果を再利用。対象コードと配布 DLL の SHA-256 が不変と確認 |

合成試験では Unity と Controller を代役に置き換えます。API 受付と物理応答を分けます。Unity Play、Import、画面表示、実ゲームのイベント接続、ネイティブ API 実機要求と物理応答は未検証です。以前の USB-C と Bluetooth の証拠は保持しました。

## 2026年10月11日の2台シミュレーション

Issue #6 の補助検証として、異なる2台の入力を合成しました。所有する実コントローラーは1台です。今回の結果は複数実機の成功を示しません。

| 検査 | 結果と範囲 |
| --- | --- |
| 実 Controller と一覧管理の合成実行 | 31 assertions 成功。ボタン、edge、軸、対応情報、振動要求、切断、参照の中立化、再接続、終了 |
| 実 native bridge の合成回帰 | CTest 1/1 成功。装置別の履歴で異なるボタンと軸を注入。振動要求と片側の切断を分離 |
| 既存 facade 回帰 | 10 assertions 成功 |
| Unity 6000.3.20f1 参照コンパイル | Runtime、Editor、検証、driver、UI以外の5サンプルの9 assemblyが成功。C#9、警告をエラー扱い |
| 配布 DLL | SHA-256 は上記の値を保持。Runtime と bridge の製品コードは変更なし |

`Tools/Test-MultipleControllers.ps1` は実 `Controller`、`XboxControllers`、ボタン定義、snapshot 定義をコンパイルします。Unity、Input System、GameInput、デッドゾーン処理は代役です。デッドゾーンの数値精度を検証する試験ではありません。native 試験は SDK 参照で実 bridge をコンパイルし、GameInput と装置を代役にします。両試験は別々に実行します。

全サンプルの結合コンパイルは uGUI の参照不足で失敗しました。今回変更していない UI サンプルはコンパイル対象から外しました。最初の新規合成試験も using 不足で失敗しました。using を修正後、31 assertions が成功しました。

最初の受信専用 probe は0台、callback 診断 `0x00000000` でした。これは実 DLL の呼び出し結果です。2台のシミュレーションとは分けます。今回の物理振動、複数実機、Bluetooth・USB-C の2台接続、Unity Play は未検証です。Issue #6 の複数実機条件は未達です。以前の USB-C と Bluetooth の実機成果は保持しました。

```powershell
pwsh -NoProfile -File Tools/Test-MultipleControllers.ps1
```

## 保持した以前の実機成果

Elite Series 2 Core / firmware 5.23.6.0 の USB-C 接続で、本体低周波、本体高周波、左 impulse trigger、右 impulse trigger の応答と停止を確認しました。各0.25、700 msを要求し、ユーザーが所定位置の振動と停止を回答しました。

以前の Unity Play は108 assertions、GATT 統合前後の native 回帰、ウォームアップ後の公開読み取り5試行0 Bも記録しています。これらを今回の再実行結果とは分けます。速度比較や実機遅延の証拠にはしません。

当時の Bluetooth 独立パドル、WGI helper、raw report の結果は [旧検証・調査履歴](archive/verification-20261010.md) に保存しました。旧ソースは commit `2f5cd9b` にあります。廃止した機能の実機成功も削除していません。

## 未検証範囲

2026年10月10日時点では、今回整理後 DLL の物理振動を再試験していません。Bluetooth のモーター、実 Unity ウィンドウのフォーカス喪失、振動中の切断・終了、複数実機、他機種、IL2CPP Player は引き続き未検証です。

振動コードと標準入力の寿命処理は保持し、合成回帰で確認しました。GitHub Actions、機器設定変更、driver 導入は行っていません。
