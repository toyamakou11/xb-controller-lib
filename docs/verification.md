# ローカル検証記録

2026年10月4日。独立4パドルの実機受け入れ条件は **未達**。全 Xbox 機種・全接続の保証ではない。

| 対象 | 条件 | 結果 |
| --- | --- | --- |
| C++ DLL | Windows x64、MSVC、C++17、SDK 3.5.283、/W4 /WX | ビルド成功、CTest 1/1 成功 |
| Unity | 6000.3.20f1、Input System 1.19.0、実 Play フレーム | 99 assertions 成功 |
| 仮想 Gamepad | 公開 API、標準ボタン・軸・エッジ・接続寿命 | 成功 |
| native 合成入力 | 4パドル、短い押下解放、同時入力・取得失敗・mapping 異常 | 成功。実機証拠とは別 |
| Editor | Legacy→Both、New/Both 保持、冪等性、Win64 import | 成功 |
| 実機 Bluetooth | Elite Series 2 Core、公式 GameInput | 独立4パドル受信は確認できず |
| 実機 USB-C | Bluetooth 切断、公式 mapper | 4個の対応情報あり。独立押下は確認できず |

Tools/Build-Native.ps1 で SDK SHA-256 を検査してビルドする。SDK と MSI は配布しない。Microsoft 署名済み GameInput 3.5.283 runtime はユーザー承認後にインストール成功を確認した。

native 回帰は ABI 不一致、初期化前 poll、callback 解除失敗の保持・再試行と mutex 外の解除、system button 再同期、履歴と時刻上限、非連続 raw index、重複・範囲外・標準ボタンとの衝突、axis と button の区別、raw 取得不足時の全状態中立化を検証する。

## 実機観測

既定 foreground policy では背景 probe の列挙は0台。同じインスタンスに GameInputEnableBackgroundInput を設定すると1台、戻すと0台という比較を実施した。本実装の背景設定はプロセス内だけで、Unity focus を別途制限する。

USB の supportedLayout=0x03ff3fff にはパドルがないが、mapper は4個を公開した。raw controller は18 buttons、公式ラベルは XboxPaddle1〜4。製品コードは API 返り値を使い、実機 index を定数にしない。

パドル単独・同時と ABXY 操作を記録した。Gamepad と ControllerButton を同じ装置で比較した40秒記録は、双方2569 samples、raw union 0xF、paddle union 0x0。再感知後の30秒記録でも標準ボタン union 0x3C、paddle union 0x0。HRESULT は成功だった。割当先の ABXY が動くことを独立パドル受信と扱わない。Supports(Paddles)=true は metadata であり、この未達を解消する証拠ではない。

プロファイル、firmware、ペアリング、振動を診断から変更していない。参考 SDL fork の別経路は非公開 Windows 構造に依存するため導入していない。

## 読み取り計測

実 Unity Play のウォームアップ後、4軸と3ボタンの公開読み取りを10万回、5試行で測定。両 backend の全試行で managed allocation 0 B。最終実行の Unity fallback は49.774〜59.488 ms、native cache は18.218〜19.047 ms。fixture が異なるので速度比較・高速化率を主張しない。poll 全体や実機遅延の測定ではない。

## 再実行と未実施

Tools/Test-Unity.ps1 -UnityEditor '<installed Editor path>' は専用一時プロジェクトを使い、既存 Unity プロジェクトを変更しない。Tools/Probe-Controller.ps1 -Seconds 30 は接続と変化 snapshot を表示する。SDK と .verification/ の証拠は Git 対象外。

実 rumble、IL2CPP Player、Xbox Wireless Adapter、複数実機 hotplug、他 Xbox 機種、異なる firmware は未検証。Unity import はローカル .verification フォルダー名の警告を出したがコンパイル・Play 検証は成功。GitHub Actions は実行・追加していない。実機独立4パドルを確認するまで Issue を完了せず PR を draft とする。
