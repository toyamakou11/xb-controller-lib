# Windows x64 IL2CPP 検証

Unity 6000.3 以降、Windows IL2CPP モジュール、既存の MSVC と CMake が必要です。Personal の Unity 6000.3.20f1 で確認しました。このツールはソフトウェアを導入しません。

```powershell
pwsh -NoProfile -File Tools/Test-Unity.ps1 -UnityEditor 'C:/Program Files/Unity/Hub/Editor/6000.3.20f1/Editor/Unity.exe'
pwsh -NoProfile -File Tools/Test-Il2Cpp.ps1 -UnityEditor 'C:/Program Files/Unity/Hub/Editor/6000.3.20f1/Editor/Unity.exe'
```

GameInput SDK の既存展開先は `-SdkPath`、CMake の実行ファイルは `-CMake` で指定できます。既定の SDK は `Tools/Build-Native.ps1` の `.verification/sdk` です。

専用の一時プロジェクトを作り、空の Scene を IL2CPP Player にビルドします。成果物とログは `.verification/issue8-player` に保存します。既存のゲームプロジェクトは変更しません。

正常な配布 DLL で ABI、初期化、poll、終了を確認します。Player 内の合成 Gamepad で通常入力、振動要求、停止、古い参照を確認します。

結果引数またはその値がない場合は終了コード1を要求します。実行ファイルが不変かも確認します。ビルド前に古い実行ファイルを削除します。

生成失敗用の DLL は、実 `Native/bridge.cpp` と失敗する `GameInputInitialize` を結合します。Player の DLL コピーだけを差し替え、runtime 生成失敗の Unity 経路と `0x8007007E` 診断を確認します。DLL 自体の欠落も別に実行します。最後に配布 DLL を復元します。

物理入力・振動、実ウィンドウのフォーカス操作、OS の GameInput runtime を削除した環境は未検証です。システムの runtime、ライセンス、ドライバーは変更しません。
