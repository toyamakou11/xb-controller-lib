# ローカル検証記録

## 現在の対象

0.2.0 の対象は標準入力と振動です。リマッピング済みパドルは A/B/X/Y などの通常入力として扱います。独立パドルの受信は合格条件に含めません。

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

これは配布 DLL の GameInput probe と実機観察です。Unity Play の検証ではありません。USB-C試験時点では、firmware version、Bluetooth、Wireless Adapter、他機種、複数実機、IL2CPP Player、フォーカス喪失と切断時の停止は未検証でした。

## 2026年10月11日のBluetooth振動実機確認

GameInput は1台を列挙し、読み取りエラーと callback 診断は `0x00000000` でした。デバイス表示名は `Xbox Wireless Controller` です。モデルと firmware version は確認していません。

配布 DLL の `xb_rumble` に各モーター `0.25`、`700 ms` を要求しました。対応マスクは `0xF` でした。各要求と停止の HRESULT は `0x00000000` でした。

| 要求 | ユーザーが確認した位置 | 要求後 |
| --- | --- | --- |
| LowFrequency | 本体左のみ | 停止 |
| HighFrequency | 本体右のみ | 停止 |
| LeftTrigger | 左トリガーのみ | 停止 |
| RightTrigger | 右トリガーのみ | 停止 |

この試験は Bluetooth 接続でのネイティブ API 要求と物理応答です。Unity Play の結果ではありません。Xbox Wireless Adapter、他機種、firmware、複数実機、IL2CPP Player、フォーカス喪失と切断時の停止は未検証です。

## 保持した以前の実機成果

Elite Series 2 Core / firmware 5.23.6.0 の USB-C 接続で、本体低周波、本体高周波、左 impulse trigger、右 impulse trigger の応答と停止を確認しました。各0.25、700 msを要求し、ユーザーが所定位置の振動と停止を回答しました。

以前の Unity Play は108 assertions、GATT 統合前後の native 回帰、ウォームアップ後の公開読み取り5試行0 Bも記録しています。これらを今回の再実行結果とは分けます。速度比較や実機遅延の証拠にはしません。

当時の Bluetooth 独立パドル、WGI helper、raw report の結果は [旧検証・調査履歴](archive/verification-20261010.md) に保存しました。旧ソースは commit `2f5cd9b` にあります。廃止した機能の実機成功も削除していません。

## 未検証範囲

2026年10月10日時点では、今回整理後 DLL の物理振動を再試験していません。Bluetooth / Wireless Adapter のモーター、実 Unity ウィンドウのフォーカス喪失、振動中の切断・終了、複数実機、他機種、IL2CPP Player は引き続き未検証です。

振動コードと標準入力の寿命処理は保持し、合成回帰で確認しました。GitHub Actions、機器設定変更、driver 導入は行っていません。
