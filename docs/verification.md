# ローカル検証記録

2026年10月4日。Elite Series 2 Core / ユーザー確認 firmware 5.23.6.0 の **Bluetooth 独立4パドルを実機確認**。USB-C の4モーター振動も確認済み。全 Xbox 機種・全接続の保証ではない。

| 対象 | 条件 | 結果 |
| --- | --- | --- |
| C++ DLL | Windows x64、MSVC、C++17、SDK 3.5.283、/W4 /WX | ビルド成功、CTest 1/1 成功 |
| Unity | 6000.3.20f1、Input System 1.19.0、実 Play フレーム | 99 assertions 成功 |
| 継続後 Unity | 同じ Editor / Input System、振動 facade 回帰を追加 | 108 assertions 成功 |
| 継続後 C++ | /W4 /WX、4モーター・所有権・raw 長の回帰 | CTest 1/1 成功 |
| GATT 統合 C++ | C++20、/W4 /WX、標準入力との edge 分離・再接続寿命 | CTest 2/2 成功 |
| 仮想 Gamepad | 公開 API、標準ボタン・軸・エッジ・接続寿命 | 成功 |
| native 合成入力 | 4パドル、短い押下解放、同時入力・取得失敗・mapping 異常 | 成功。実機証拠とは別 |
| Editor | Legacy→Both、New/Both 保持、冪等性、Win64 import | 成功 |
| 実機 Bluetooth | Elite Series 2 Core、公式 GameInput | 独立4パドル受信は確認できず |
| 実機 Bluetooth supplement | 同じ機器、公開 WinRT vendor GATT | 独立4パドル・同時押下解放・ABXY からの独立性を確認 |
| 実機 USB-C | Bluetooth 切断、公式 mapper | 4個の対応情報あり。独立押下は確認できず |

Tools/Build-Native.ps1 で SDK SHA-256 を検査してビルドする。SDK と MSI は配布しない。Microsoft 署名済み GameInput 3.5.283 runtime はユーザー承認後にインストール成功を確認した。

native 回帰は ABI 不一致、初期化前 poll、callback 解除失敗の保持・再試行と mutex 外の解除、system button 再同期、履歴と時刻上限、非連続 raw index、重複・範囲外・標準ボタンとの衝突、axis と button の区別、raw 取得不足時の全状態中立化を検証する。

## 実機観測

既定 foreground policy では背景 probe の列挙は0台。同じインスタンスに GameInputEnableBackgroundInput を設定すると1台、戻すと0台という比較を実施した。本実装の背景設定はプロセス内だけで、Unity focus を別途制限する。

USB の supportedLayout=0x03ff3fff にはパドルがないが、mapper は4個を公開した。raw controller は18 buttons、公式ラベルは XboxPaddle1〜4。製品コードは API 返り値を使い、実機 index を定数にしない。

パドル単独・同時と ABXY 操作を記録した。Gamepad と ControllerButton を同じ装置で比較した40秒記録は、双方2569 samples、raw union 0xF、paddle union 0x0。再感知後の30秒記録でも標準ボタン union 0x3C、paddle union 0x0。HRESULT は成功だった。割当先の ABXY が動くことを独立パドル受信と扱わない。Supports(Paddles)=true は metadata であり、この未達を解消する証拠ではない。

上記のパドル診断ではプロファイル、firmware、ペアリング、振動を変更していない。後続の振動試験は別項に記録する。後続の公開 Bluetooth GATT supplement は次項に記録する。非公開 Windows サービス構造は導入していない。

## Bluetooth 独立パドルの統合検証

同じ ContainerId の一意な paired LE endpoint に、公開 metadata から取得した address で接続した。17-byte vendor report を120秒受信し、898 samples、gaps=0。ユーザーは4パドル単独、4個同時、ABXYのみの操作を完了したと回答した。raw nibble は単独1/2/4/8、同時F、全解放0で、ABXYのみの区間では0だった。前の30秒試行は操作開始前に終了して0 samplesだったため受信成功と扱わない。

位置別の追加120秒記録は705 samples、gaps=0。最初に複数パドル操作が含まれた後、指示した左手上・左手下・右手上・右手下の単独操作区間で `4→0→8→0→1→0→2→0` を確認した。ユーザーは順番の操作完了を回答した。これはコードに観測 index を入れるためではなく、参考プロトコルの物理左右と公開 enum の命名を対照する検査である。

配布 DLL の `Tools/Test-Paddles.ps1` を120秒実行し、7626 polls、shutdown S_OK、プロセス終了0。ユーザーの4単独・同時・ABXYのみ操作を公開 ABI で記録した。左右上/下は facade 順に1/2/4/8、pressed union=F、released union=F、同時状態Fと全解放0を確認した。ABXYのみの4/8/10/20変化区間ではパドル値と edge は0を維持した。正常な GameInput 履歴再同期は診断し、その後の GATT 入力を受信した。

実装前の独立設計レビューと最終実装レビューを実施した。標準履歴と GATT の比較領域、同じ container の曖昧な token、Detach と retry の競合、切断後の retry、offline CCCD 復元と新接続の購読順を修正した。合成回帰は短い押下/解放、全同時、誤長、古い generation、focus resync、標準履歴失効、失敗診断の分離、shutdown 資源保持、retry gate と旧 cleanup 完了待ちを検証した。Cancellation の terminal 前に資源を破棄しない。

固定 firmware whitelist は使わず、identity・service/characteristic・報告長を検査する。ただし実機確認は5.23.6.0 / profile 1であり、未知 firmware の保証ではない。CCCD の他 client との競合保護は best effortで、原子的な所有権はない。実機再接続・focus の結果は別に記録する。

## 読み取り計測

最終 DLL（SHA-256 `602FAAA8D310424C70A2C20D4CA0E380F12D1D56C8634EE83C09F6CA5F5F6CC5`）でも CTest 2/2、Unity Play108 assertions、公開読み取りの全5試行0 Bを再確認した。最初の150秒 lifecycle待機ではユーザーの操作を捕捉できず、物理 lifecycle 成功とは扱わない。待機を延長した最終記録では、接続0台から Bluetooth 接続を受けて新 token を列挙し、再接続後の4独立パドル入力を確認した。ユーザーも再接続・操作完了を回答した。25,150 polls、397,600 msで終了信号により停止、shutdown S_OK、プロセス終了0。

最終記録中、押下状態を検出した時に `xb_resync()` を実行し、その後の追加pressed edgeはなく、実際の解放を1回記録した。5秒の保持時間や Unity の実ウィンドウfocus喪失はこの記録で確認していない。旧 token が存在する同一 collector 内での物理切断→新 token の比較も未検証であり、同条件の中立化・generation・cleanup待ちは合成回帰と独立レビューで確認した。

native の2台合成検証では容量不足時に両台の履歴を消費しないこと、拡張した配列の異なる token、対象台だけの振動所有権、片側切断後の他方の保持、古い token の拒否、再接続の新 token を確認した。複数実機の同時接続を検証した意味ではない。

実 Unity Play のウォームアップ後、4軸と3ボタンの公開読み取りを10万回、5試行で測定。両 backend の全試行で managed allocation 0 B。GATT 統合後の最終実行の Unity fallback は50.869〜51.763 ms、native cache は17.966〜18.257 ms。fixture が異なるので速度比較・高速化率を主張しない。poll 全体や実機遅延の測定ではない。

## Xbox 振動と raw GIP の継続検証

2026年10月4日。実装前の独立設計レビューと変更後の独立レビューを実施した。切断時の所有出力停止、callback 解除失敗前の停止、致命的な読み取り失敗時の停止、live 接続検査、制限後の能力検査を追加した。native 合成検証は4モーターと16種類の能力組合せ、NaN/Infinity、拒否時の所有権保持、正常/失敗履歴再同期、切断、未所有出力、終了再試行を確認した。Unity は記録用 Gamepad の公開出力 override で本体出力、値の制限、非対応 trigger、フォーカス喪失・復帰・無効化を検証した。実機振動の証拠とは別である。

今回の実 Play は108 assertions成功、公開読み取り5試行の0 B条件も成功した。sandbox 内の最初の実行はライセンスサービスへの接続に失敗し、通常のローカル環境で再実行して成功した。ホストCIは実行していない。

USB 接続の受信専用 raw probe は1台、motor mask=0xF、inputKinds=0x01040007、input report 1個（kind=Input、id=0、size=18）、output report 0個を返した。GetRawDataSize は0であり、サイズ不一致として拒否、samples=0、終了コード1だった。空 payload を成功やパドル状態0の実測と扱わない。GameInput が返した firmwareVersion は0.0.0.0で、ユーザー確認の5.23.6.0を API で再確認できた意味ではない。合成テストは正常raw、空payload、部分コピー、未知ID、誤kind、report欠落を検証した。

| 実機モーター | USB-C | Bluetooth / Wireless Adapter |
| --- | --- | --- |
| 本体低周波（左） | 所定位置の振動と停止をユーザー確認 | 未検証 |
| 本体高周波（右） | 所定位置の振動と停止をユーザー確認 | 未検証 |
| 左 impulse trigger | 所定位置の振動と停止をユーザー確認 | 未検証 |
| 右 impulse trigger | 所定位置の振動と停止をユーザー確認 | 未検証 |

`Tools/Test-Rumble.ps1` は同じセッション内で接続を選択し、transport を記録する。各モーターを個別に0.25で700 ms出力し、0出力後に位置・他モーターの反応・停止の観測を入力する。対応情報のないモーターは出力せず、finally でも所有出力を停止する。`-ListOnly` は出力を行わず能力を確認する。接続順や別プロセスのtokenを永続IDとして用いない。

2026年10月4日の対話式実機試験では、ユーザーの Elite Series 2 Core（確認済み firmware 5.23.6.0）、USB-C、選択セッションの motor mask=0xF を使用した。低周波、高周波、左trigger、右triggerの順で1回ずつ、他チャンネルを0にして0.25 / 700 msの要求を送った。4回すべて要求と停止のHRESULTはS_OK。ユーザーは各回、所定の位置で振動を感じ、その後停止したと回答した。試験プロセスはfinallyの終了処理後にexit 0で終了した。これはAPI成功だけでなくユーザー観測による物理応答の証拠であり、振動強度の計測、他モーターへの機械的な伝達量、同時4出力を検証した意味ではない。

初回試験は入力待ちで履歴が失効した後、正常な最新値への再同期（0x838A0004）を試験スクリプトが致命的エラーと扱い、モーター出力前に中断した。facadeと同じ再同期状態だけを許可する修正後、上記4回の実機試験が成功した。他の負の読み取り結果、失われた接続、非対応モーターの拒否は保持した。DLLとruntimeコードはこの修正で変更していない。

```powershell
pwsh -NoProfile -File Tools/Test-Rumble.ps1 -ListOnly
pwsh -NoProfile -File Tools/Test-Rumble.ps1
# ビルド後の受信専用診断。期間は接続ごと、0なら初期状態だけ。
.\.verification\native-build\Release\XbControllerRawProbe.exe 30
```

独立4パドルは上記 Bluetooth supplement で確認した。SDL fork の zlib ライセンスと Microsoft header の MIT / runtime の再頒布条件を区別して確認した。配布 DLL は protocol UUID/field の根拠を引用した独自 GATT 実装で、private service offset・USB enable payload を同梱していない。USB provider の受信専用評価は Git 対象外の別 EXE に限る。

## 再実行と未実施

### 2026年10月8日の確認

- 再開時: PR #2・Issue #1は open。headは `b8209c6`。作業ツリーは clean。公開PRの77ファイルはローカルblobと一致。
- USB: WGI と GameInput の同一装置を結ぶ公開経路は未確立。既存の失敗した照会は再実行しない。
- [FindDeviceFromObject](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/deprecated/interfaces/igameinput/methods/igameinput_finddevicefromobject?view=gdk-2604): v0でも未実装。v1で削除。
- [NonRoamableId](https://learn.microsoft.com/en-us/uwp/api/windows.gaming.input.rawgamecontroller.nonroamableid?view=winrt-26100): application別のID。公開GameInput/PnP IDへの変換契約は未確認。
- [Factory API](https://learn.microsoft.com/en-us/uwp/api/windows.gaming.input.custom.gamecontrollerfactorymanager?view=winrt-26100): 登録解除なし。別EXE化も装置の同一性を解決しない。
- [SDL参考source](https://github.com/hifihedgehog/SDL/blob/1d2bf1f9b334ae791266bf332d534d73f34f2ccc/src/joystick/windows/SDL_xinput_paddle_wgi.cpp): provider ID解析・DLL固定・zlib noticeを確認。追加コードは不採用。
- 接続診断: GameInput 1台・中立値・S_OK。接続方式・firmware・独立パドル受信の証拠とは扱わない。

USB採用には正確な公開identityと安全なcallback終了の証拠が必要。独立評価でも現状の製品採用は見送る。Bluetoothの受け入れ条件は保持する。

### CodeRabbit 指摘への対応

- 容量交渉: 初回＋最大4回。上限後はControllerと診断を保持。他の取得失敗は無効化。
- ビルド探索: vswhereの終了コード・空白パス・cmake.exeの存在を検査。
- 合成回帰: 実facadeの10 assertions成功。旧版は失敗。探索ASTの5条件も成功。
- native: 通常ビルドとCTest 2/2成功。配布DLLのSHA-256は `602FAAA8D310424C70A2C20D4CA0E380F12D1D56C8634EE83C09F6CA5F5F6CC5`。
- Unity: 今回のPlayはlicenseエラーexit198で開始前に失敗。実Unity参照で全runtimeをC#9・Windows define・警告をエラー扱いでコンパイルし、成功。
- 独立設計・最終レビュー: 承認。追加実機試験・Actionsは未実施。

今回の合成回帰と参照コンパイルは、以前の実Play108 assertionsや実機試験とは別。

```powershell
pwsh -NoProfile -File Tools/Test-NativePolling.ps1
```

### USB provider 経路の評価結果

非公開 ControllerInitialize COM contract の sourced IID と aggregation を使う別 EXEで、公開 WGI factory/sink の初期化と公式 `TryGetFactoryControllerFromGameController` による controlling identity の一致を確認した。最初の背景受信8秒は正常報告0であり、受信成功と扱わない。foreground の試験ウィンドウをユーザーが操作した記録では、normal60、resumed1、suspended1、47-byte LowLatency/id0 報告を受信した。ユーザーの A・4パドル操作で byte14 の独立 `4/1/8/2` と解放0を確認した。装置への enable 命令は送っていない。

ただし WGI と既存 GameInput の同一装置を結びつける製品用条件は成立しなかった。公式 `NonRoamableId` と `GetProviderId` を変更せず `FindDeviceFromPlatformString` に渡したが、両方0x80070490。`GetParentProviderId` は空だった。同じ非空文字列の公開 PnP Locate/interface property 照会も失敗し、ContainerId を取得できなかった。空文字列で machine root を選ばないよう拒否した。VID/PID、接続順、文字列変形、service offset による推測で補完しない。

全入力を WGI に置き換える案もレビューしたが、最新 snapshot だけでは既存の短い edge/history 契約を保てず、Guide/Share・実モーター能力にも同等の公開情報がない。4 vibration 値を少ないモーターへ合成する WGI の仕様を独立4モーターの能力と扱わない。従って製品は GameInput 標準入力・出力と公開 Bluetooth GATT supplement を保持する。USB のこの別 EXE は検証資料だけで、UPM/DLLに同梱しない。USB 独立パドルの製品対応を達成したとは報告しない。

### Issue #3: USB 実装の保留条件（2026年10月8日）

[Issue #3](https://github.com/toyamakou11/xb-controller-lib/issues/3) の独立設計レビューでは、上記の受信・identity 評価を再利用し、現時点の製品採用を保留した。失敗した実機照会は再実行していない。

- identity: WGI 内の controlling identity 一致は GameInput との同一性ではない。公開 ID/PnP の照会失敗を VID/PID・接続順・文字列加工で補完しない。
- DLL 寿命: [公開 factory API](https://learn.microsoft.com/en-us/uwp/api/windows.gaming.input.custom.gamecontrollerfactorymanager?view=winrt-26100) に登録解除はなく、参考実装は module pin を使う。非公開 ControllerInitialize と process 終了に依存する別 EXE の結果は、DLL の callback 停止・終了・再初期化の証拠にならない。
- 契約: WGI 全置換では短い入力 edge/history、Guide/Share、実4モーター能力の同等性を確認できない。ABI v1・80 bytes と既存 backend を保持し、USB decoder・enable 命令は追加しない。

再開には、未試行の公開仕様に基づく厳密な装置連結と、callback を停止して所有資源を安全に解放できる経路の両方が必要。その後に4個別・同時・解放・ABXY独立性と再接続・終了を実機検証する。Issue は未完了のまま保持する。

今回のローカル確認は既存 native CTest 2/2 と実 facade 合成10 assertions が成功。文書のみの変更で、再ビルド・Unity Play・追加実機試験は実施していない。controller 設定、Actions、paid service は変更・使用していない。

Tools/Test-Unity.ps1 -UnityEditor '<installed Editor path>' は専用一時プロジェクトを使い、既存 Unity プロジェクトを変更しない。Tools/Probe-Controller.ps1 -Seconds 30 は接続と変化 snapshot を表示する。SDK と .verification/ の証拠は Git 対象外。

振動のBluetooth / Xbox Wireless Adapter、実機でのフォーカス喪失・振動中の切断・終了停止、同時4モーター出力、IL2CPP Player、複数実機 hotplug、他 Xbox 機種、異なる firmware は未検証。振動の所有権・focus・切断・終了の停止条件は合成回帰で確認している。Unity import はローカル .verification フォルダー名の警告を出したがコンパイル・Play 検証は成功。GitHub Actions は実行・追加していない。Bluetooth の独立4パドル条件と最終 Unity 再実行は成功。PR の merge はユーザー承認なしに実行しない。USB 独立パドルの製品対応は未達として扱う。
