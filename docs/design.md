# 設計と受け入れ条件

## 目的と達成条件

Git URL で追加し、Actions の手動作成なしで標準 Xbox 入力を扱う UPM パッケージ。独立4パドルは必須条件であり、metadata と合成テストを実機達成と扱わない。現時点では実機条件は未達。[検証記録](verification.md) を参照。

- Unity 6000.3、Input System 1.19.0 の実 Editor でコンパイル・Play 実行できる。
- 標準ボタン、軸、押下・解放、接続・切断・無効化・再初期化を扱う。古い参照は中立値。
- 旧入力だけの Editor は Both に変更して再起動を案内する。既存 New/Both は保持。
- 独立4パドルの単独押下・解放・同時入力と ABXY からの独立性を実機確認する。
- ウォームアップ後の公開読み取りは managed GC 割り当て0 B。遅延の証拠とは別。
- 機種名、VID/PID、固定台数、生番号、ABXY 推測で入力を判定しない。プロファイルや firmware を自動変更しない。

## 構成と公開契約

C# facade `Runtime/XboxControllers.cs` はメインスレッド専用の読み取り専用一覧を提供する。Windows x64 は C++17 GameInput v3 bridge、他 OS と初期化失敗時は Unity Gamepad。SDK 3.5.283 を固定検査してビルドし、runtime は黙ってインストールしない。backend は初期化から終了まで固定。別 backend の装置を接続順で合成しない。

`XboxButton` は公式の名前付き GameInput 定義に対応する。Unity fallback は意味的な公開 controls を使う。`Supports` は対応 metadata、各 pressed API は受信した状態であり、物理入力の保証とは異なる。スティックは Input System の deadzone 設定を再利用する。

C ABI は version 1、cdecl、pack 8、80-byte snapshot、固定幅整数と int32 HRESULT。版・サイズを検査し bool を境界へ置かない。接続 token は DLL の生存期間中リセットせず、切断・再初期化後の参照を無効化する。機種IDではない。

callback は COM 所有参照と mutex で端末一覧を管理する。終了フラグは mutex 内、解除は mutex 外。解除失敗は context を保持し診断と再試行を可能にする。C ABI 外へ例外を出さない。

GameInput インスタンスだけに背景入力を許可して列挙を安定させ、Play 中は C# が Unity フォーカスで中立化する。Dynamic/Fixed/Manual の設定に対応する更新だけでポーリングし BeforeRender は消費しない。Editor の非 Play 更新は診断用。

reading 履歴はポーリング開始時刻まで有限に消費し、短い押下・解放を両方保持する。失効は最新値へ同期し失われたエッジを作らない。取得失敗は全状態を中立化する。callback のエラーと正常端末の取得を分離する。

振動は公開モーターだけに要求し、有限値を0〜1に制限してから対応可否を検査する。非対応モーターへの正の要求と非有限値は、既存出力を変更せず拒否する。`low/high` は本体の低周波/高周波、`leftTrigger/rightTrigger` は左右の impulse trigger に対応する。Unity fallback は本体2モーターだけを公開する。

ライブラリが開始した振動だけをフォーカス喪失・切断・致命的な読み取り失敗・終了時に停止し、自動再開しない。native は live 接続状態を出力直前に確認し、callback 解除前に所有出力を停止する。解除失敗でも停止済みの context を保持して再試行する。正常な履歴再同期では停止しない。GameInput の `SetRumbleState` は void であり、`SetRumble=true` は有効な要求の送信を表す。実際のモーター応答・停止・通信失敗を保証する戻り値ではない。GameInput の不足モーターへの emulation を独立モーターの成功と扱わない。

## パドルの公式マッピング

supportedLayout だけで判定せず、接続時に IGameInputMapper から公式4パドルの mapping を取得する。Button element で公開 count 内の index だけを採用する。パドル同士や標準ボタンと同一 index は独立入力として採用しない。観測した実機番号をコードに書かない。

raw buffer は装置の公開 count で接続時のみ確保する。返却 count を検査し、標準 state と raw state の双方が同じ reading で成功した後だけ commit する。対象パドル bit は raw 値で置換する。未受信値を ABXY から補完しない。

## 機器の制約と追加調査

Elite Series 2 Core は別売4パドルに対応する。トリガーロック・張力調整は追加キーではない。Unity Windows XInput は独立パドルを公開しない。Guide/Share は GameInput system callback と対応情報に従い、Profile/Pair を一般ゲーム入力や Share と見なさない。

USB は mapper と raw label に4パドルを公開したが押下値は0のままだった。SDK の enum 追加は手元の機器・接続の実入力保証ではない。

参考 SDL fork も公式 GameInput のパドル実装を撤回し別経路へ移行した。Bluetooth は vendor GATT UUID と payload、USB は非公開 Windows サービス構造、追加報告命令、OS ファイル版検査に依存する。WGI の SendReceiveMessage 自体は公開 API だが、参考実装の provider と端末の関連づけ・raw 取得は非公開構造を使う。参考文書は firmware 5.23.6.0 の実機試験未実施を明記している。未文書化 offset と機種 ID は取り込んでいない。

SDK 3.5.283 の公開 `GameInputKindRawDeviceReport/GetRawReport` を使う受信専用診断 `Native/raw_probe.cpp` を追加した。同じ公式 device pointer の reading を使い、descriptor の kind/id/size、実データ長、コピー長がすべて一致した場合だけ報告を記録する。公開 metadata で接続時にバッファを確保し、通常捕捉では再利用する。履歴を開始時刻の cutoff と接続ごとの指定時間で制限し、履歴失効・切断を明示する。列挙 callback は捕捉前に mutex 外で解除し、失敗時は捕捉を中断して context をプロセス終了まで保持する。再接続は再実行で新しい attachment として扱う。

公開 raw 出力 API は存在するが、descriptor の ID とサイズだけではパドル有効化命令の framing や状態の意味を確定できない。現在の USB 実機では input descriptor 18 bytes に対し実データ0 bytes、output descriptor 0個だった。値を ABXY から補完せず、decoder と命令送信は実装していない。追加 backend の production 採用には、公開プロトコルの根拠と独立パドルの受信証拠が残る。firmware の完全一致 whitelist や downgrade を条件にしない。

## 独立レビューへの対応

実装前の2回の独立設計レビューを反映した。対応 API、振動所有権、Editor 条件、再接続、0 B 条件、版整合、callback 終了順、履歴失効、有限消費、ABI と実機合否を確定した。初期の C# 標準入力のみ・任意 control path 案は、必須パドルにより名前付き enum と GameInput に置き換えた。

raw mapping 設計も実装前に独立レビューし、重複 index、返却 count、部分成功、中立化、Gamepad 値との競合を修正した。実装レビューでは plugin import、実 Play 検証、フォーカス復帰の古い状態、標準ボタンとの index 衝突を修正して回帰検証した。最後の追加レビュー依頼はエージェント使用上限で実行できず、親エージェントが最終差分を確認した。

## 一次資料

- [Xbox Elite Series 2 Core](https://www.xbox.com/en-US/accessories/controllers/xbox-elite-wireless-controller-series-2-core)
- [XINPUT_GAMEPAD](https://learn.microsoft.com/en-us/windows/win32/api/xinput/ns-xinput-xinput_gamepad)
- [GameInput SDK と履歴](https://github.com/microsoftconnect/GameInput)
- [公式4モーター出力](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/interfaces/igameinputdevice/methods/igameinputdevice_setrumblestate)
- [公式 raw GIP 受信](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/interfaces/igameinputreading/methods/igameinputreading_getrawreport)
- [公式 raw 出力](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/interfaces/igameinputdevice/methods/igameinputdevice_sendrawdeviceoutput)
- [公開 WGI message API](https://learn.microsoft.com/en-us/uwp/api/windows.gaming.input.custom.gipgamecontrollerprovider.sendreceivemessage)
- [Unity Gamepad](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Gamepad.html)
- [撤回された GameInput パドル実装](https://github.com/hifihedgehog/SDL/blob/feat/hidmaestro-filter/docs/README-gameinput-paddles.md)
- [参考実装の別経路](https://github.com/hifihedgehog/SDL/blob/feat/hidmaestro-filter/docs/README-xinput-paddles.md)
