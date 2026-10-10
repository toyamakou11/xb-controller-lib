# 2026年10月10日までの検証・調査履歴

この文書は0.1.0の記録を保存したものです。2026年10月10日に目的を標準入力と振動へ戻しました。
独立パドルの対応条件、廃止したツール、旧受入条件は現在の仕様ではありません。
旧コードは commit 2f5cd9b の履歴で確認できます。現在の検証は ../verification.md を参照してください。
以下の実機・合成検証と調査結果は、当時の条件のまま保持します。

---

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

実装保留時のローカル確認は既存 native CTest 2/2 と実 facade 合成10 assertions が成功。その時点では文書のみの変更で、再ビルド・Unity Play・追加実機試験は実施していない。controller 設定、Actions、paid service は変更・使用していない。

### Astra による追加評価

`gpt-6-astra` の助言で、[GameInput #27 の foreground 制約報告](https://github.com/microsoftconnect/GameInput/issues/27)を新仮説として検証した。受信専用の別 EXE に Win32 窓と message pump を設け、focus 後の新しい reading だけを評価した。SDK 3.5.283、同じ device pointer、descriptor/kind/id/actual/copied 長を検査し、空値は採用していない。MSVC /W4 /WX ビルド成功。

ユーザーは USB-C 接続と4個別・同時・解放・ABXYのみの操作完了を回答した。18-byte/id0 の有効 raw 101件を受信し、foreground batch 内は93件、invalid=0、focus 計37,234 ms。操作完了後に窓を正常終了した。変化は byte1 と byte4〜7、byte12〜17は全件0で、独立パドルの証拠は得られなかった。以前の空 payload 結果は背景診断の結果として保持する。

Astra の独立レビューも raw 受信と USB パドル達成を分離した。focus は batch ごとの検査、履歴 gap は386件、同値 baseline は変化ログから省略され得るため、連続履歴・edge・lifecycle の実機合格とは扱わない。18-byte framing の意味は未確定。WGI decoder・enable 命令・設定変更は追加せず、Issue #3 と PR #21 の実装保留を維持する。

### GameInput foreground mapper の追加確認（2026年10月9日）

公式 GameInput だけを使う受信専用 foreground 窓で1台を列挙し、18個の controller button と GameInput mapper の4個の paddle mapping を取得した。mapping は異なる Button index `14/15/16/17`、label は公式 `XboxPaddle1〜4`。同じ `GameInputKindGamepad` reading から標準 state と全 controller button state を読み、focus 後の新しい timestamp に限って記録した。21件の state 変化で標準ボタンは変化したが、mapper が指す4 index はすべて0だった。通常の button state 配列では index `0〜3` に変化があり、paddle index `14〜17` は0のままだった。

ユーザーは指示した個別・同時・ABXY 操作を完了したと回答した。記録に操作段階の印はなく、650件の履歴 gap を伴う試験を中断したため最終終了行もない。`GAMEINPUT_E_REFERENCE_READING_TOO_OLD` から再同期した後の21件だけを記録したので、個別位置・同時押下・解放・ABXY 独立性を段階別に立証した扱いにはしない。この結果は foreground 条件下でも GameInput の公式 paddle mapper 値を得られなかった観測であり、GameInput の短い edge/history を満たす新しい実装経路ではない。試験中に機器への出力、設定変更、enable 命令は行っていない。

同じ GameInput device の公開 `pnpPath` を公開 Configuration Manager API で解決し、その HID/USB instance と USB 親 instance の `ContainerId` が GameInput `containerId` と一致することを確認した。これは GameInput device の PnP container を特定する証拠であり、WGI `NonRoamableId` / provider ID から同じ container へ結ぶ公開契約や安全な factory callback 終了の証拠ではない。

### USB-C foreground parent / hidden helper の確認（2026年10月10日）

受信専用 helper を USB-C 接続で起動した。factory 登録、controller 追加、association callback の時点で foreground owner は親 harness だった。ユーザーは10秒の入力区間で物理入力を行ったが、class 1 / id 0 / 47-byte report は0件だった。hidden helper への入力配送は確認できなかった。

手動停止では helper process が exit code 0 で終了し、pipe reader failure はなかった。停止後に別 helper process を起動し、factory 登録と association を再確認した。プロセス単位の停止と再初期化は成功した。製品 DLL の unload と factory callback の解除は未検証である。全3 session の要約は `.verification/luna-lifecycle-search/helper-focus/foreground-parent-helper-result-20261010.md` に保存した。最新 session の記録は `.verification/luna-lifecycle-search/helper-focus/build/Release/helper-focus-result.txt` に保存した。

ユーザーが controller の profile slot 3 を有効にした追試では、input phase は QueryPerformanceCounter で約9.99秒続いた。開始時と終了時の foreground owner は親 harness だった。class 1 / id 0 / 47-byte report は0件で、helper は手動停止後に exit code 0 で終了した。reader failure はなかった。ログは物理ボタン操作の有無を記録しないため、この追試だけでは操作段階を検証できない。

visible live monitor を追加した後の session 2 では、factory 登録、controller 追加、association 時の foreground owner は helper PID `27416` だった。画面と callback log は class 1 / id 0 / 47-byte report を受信し、全ての記録済み accepted report で `foregroundPid=helperPid` だった。画面では byte 14 下位4 bitが `0x00`、`0x02`、`0x0F`、`0x09` などに変わり、paddle 名も `none`、`Right2`、4個全て、`Left2,Right1` などへ更新された。これは foreground helper の WGI report に paddle 状態と一致する値が届く実機観測である。GameInput との公開 identity join と製品 DLL 内の安全な callback 終了・再初期化は未検証のため、製品対応の根拠にはしない。

画面を直接確認した次の helper session は profile slot 3 だった。`Left1=0x04`、`Left2=0x08`、`Right1=0x01`、`Right2=0x02` を個別に表示した。各 paddle を離すと `0x00` に戻り、4個同時では `0x0F` を表示した。ABXY のみを試すよう指示した直後の画面は `none` だったが、操作そのものは log に記録されていない。対応する log sample は class 1 / id 0 / 47-byte、foreground owner は helper PID `31764` だった。

次に選択した profile slot 2 で helper session `2` を実行した。factory association は成功し、47-byte report を受信した。`Left1=0x04`、`Left2=0x08`、`Right1=0x01`、`Right2=0x02` を再確認し、各解放は `0x00` に戻った。2個の組み合わせ `0x09` と4個同時 `0x0F` も受信した。同時解放中は `0x0D`、`0x0C`、`0x08`、`0x00` と変化した。全 accepted report の foreground owner は helper PID `33620` だった。ABXY 試験を指示した後は byte 14 が `0x00` のまま他 payload byte が変化したが、ABXY 操作自体は log に記録されていない。USB 再接続後の再現は未確認である。

ユーザーは次の順に試験したと確認した。slot 3、slot 2、slot 1。slot 1 の helper session `3` は factory association に成功し、class 1 / id 0 / 47-byte report を199件受信した。全ての accepted report で foreground owner は helper PID `988` だった。byte 14 下位4 bitから `Left1=0x04`、`Left2=0x08`、`Right1=0x01`、`Right2=0x02` の個別状態、各組み合わせ、および `0x0F` を観測した。記録は明示的な段階マーカーを持たないため、押下保持の時間や ABXY 操作との対応は立証しない。

この試験は GameInput と WGI の identity join を検証していない。USB-C 独立 paddle の製品実装は保留する。

Tools/Test-Unity.ps1 -UnityEditor '<installed Editor path>' は専用一時プロジェクトを使い、既存 Unity プロジェクトを変更しない。Tools/Probe-Controller.ps1 -Seconds 30 は接続と変化 snapshot を表示する。SDK と .verification/ の証拠は Git 対象外。

振動のBluetooth / Xbox Wireless Adapter、実機でのフォーカス喪失・振動中の切断・終了停止、同時4モーター出力、IL2CPP Player、複数実機 hotplug、他 Xbox 機種、異なる firmware は未検証。振動の所有権・focus・切断・終了の停止条件は合成回帰で確認している。Unity import はローカル .verification フォルダー名の警告を出したがコンパイル・Play 検証は成功。GitHub Actions は実行・追加していない。Bluetooth の独立4パドル条件と最終 Unity 再実行は成功。PR の merge はユーザー承認なしに実行しない。USB 独立パドルの製品対応は未達として扱う。
