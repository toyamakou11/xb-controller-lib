# 設計と受け入れ条件

## 目的

Unity でコントローラーを扱う実装負担を減らす。既存の Unity Input System と GameInput を再利用し、標準入力と振動を共通 API で提供する。

Xbox Accessories でリマッピングしたパドルは、割当先の通常ボタンとして読む。独立物理パドル、USB GIP raw report、WGI helper、vendor GATT は製品範囲に含めない。調査履歴は保存する。

Xbox Wireless Adapter は対応・検証対象外とする。

## 受け入れ条件

- UPM で導入し、Unity 6000.3 以降と Input System 1.19.0 でコンパイルできる。
- 標準ボタン、軸、押下・解放、接続、切断、無効化、再初期化を扱う。
- 古い Controller 参照は中立値を返す。
- 対応する振動出力だけを要求し、所有出力を停止する。
- 旧入力設定の Editor は Both へ変更し、再起動を案内する。既存 New/Both は保持する。
- 実機、合成、参照コンパイルの結果を区別する。機器設定を自動変更しない。

## 入力経路

`Runtime/XboxControllers.cs` はメインスレッド専用の読み取り専用一覧を提供する。Unity 経路は `Gamepad.all`、標準 controls、edge API、振動 API を利用する。Input Actions やデバイスドライバーを独自実装しない。

Windows x64 は既存の C++17 GameInput bridge を既定にする。4モーター振動と入力履歴を保持するためである。初期化失敗時と他 OS は Unity Gamepad を使う。backend は初期化から終了まで固定し、切り替えは Shutdown 後に行う。

GameInput の標準状態は `GetGamepadState()` から読む。公開標準 layout と C/Z の範囲だけを公開する。独立ボタン用 mapper と `GetControllerButtonState()` は使わない。Guide/Share は公式 system callback と能力情報を使う。Profile/Pair はゲーム入力にしない。

## 公開契約

`Supports` は対応情報であり、押下状態と分ける。標準ボタンの名前と値を保持する。0.2.0 はパドル専用 enum を削除する。リマッピング済みパドルの利用側は割当先ボタン名を使う。

C ABI は version 1、cdecl、pack 8、80-byte snapshot を保持する。固定幅整数と int32 HRESULT を使う。接続 token は機種IDやプレイヤー番号ではない。切断・再初期化後の古い token を無効にする。

callback は COM 所有参照と mutex で一覧を管理する。終了フラグと振動停止は mutex 内で処理し、callback 解除は mutex 外で行う。解除失敗時は context を保持して再試行する。C ABI 外へ例外を出さない。

GameInput instance は背景入力を許可して列挙する。ゲームへの入力公開は Unity のフォーカスで制限する。選択された Dynamic/Fixed/Manual 更新だけで native を読む。BeforeRender は履歴を消費しない。

履歴は poll 開始時刻まで消費する。同じ更新内の押下と解放を両方保持する。履歴失効は最新値への同期として診断する。読み取り失敗時は入力を中立化する。スティックは Input System のデッドゾーン設定を再利用する。

## 振動

`SetRumble(low, high, leftTrigger, rightTrigger)` は本体低/高周波と左右 impulse trigger を表す。Unity 経路は本体2モーターだけを公開する。

非有限値と非対応モーターへの正の要求は、既存出力を変更せず拒否する。有限値は0〜1へ制限する。GameInput の `SetRumbleState` は void であり、受付と物理応答を区別する。

ライブラリが開始した振動だけをフォーカス喪失、切断、致命的な読み取り失敗、終了で停止する。復帰後は自動再開しない。native は出力前に live 接続状態を確認する。正常な履歴再同期では振動を止めない。

## 検証と資料

標準入力と振動の合成回帰を保持する。公開読み取りの managed allocation と実機遅延は別の指標である。実機互換性と未検証条件は [検証記録](verification.md) に記載する。ゲーム操作サンプルは基本ライブラリの受入条件に追加しない。

- [Unity Gamepad](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Gamepad.html)
- [GameInput SDK](https://github.com/microsoftconnect/GameInput)
- [公式4モーター出力](https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/input/gameinput/interfaces/igameinputdevice/methods/igameinputdevice_setrumblestate)
- [旧検証・調査履歴](archive/verification-20261010.md)
