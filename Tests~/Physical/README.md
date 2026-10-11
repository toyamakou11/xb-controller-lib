# USB-C の実機ライフサイクル確認

Unity 6000.3 以降、既存の Windows IL2CPP モジュールと MSVC、USB-C の1台が必要です。既存のゲームプロジェクトは変更しません。

```powershell
pwsh -NoProfile -File Tools/Test-Unity.ps1 -UnityEditor 'C:/Program Files/Unity/Hub/Editor/6000.3.20f1/Editor/Unity.exe'
pwsh -NoProfile -File Tools/Test-UsbLifecycle.ps1 -UnityEditor 'C:/Program Files/Unity/Hub/Editor/6000.3.20f1/Editor/Unity.exe'
```

`-BuildOnly` はビルドだけを確認します。通常実行は専用 Player の試験窓を表示します。ボタンを押すまで振動を要求しません。開始した振動は最大60秒で停止します。

1. USB-Cで1台を接続します。
2. 「1」を押し、別の窓をクリックします。
3. 振動の停止を観察します。
4. 試験窓へ戻り、自動再開がないことを観察します。
5. 「2」を押し、USB-Cを外します。
6. 停止を観察します。
7. Aを保持して再接続します。
8. 窓の継続と自動再開がないことを観察します。
9. 「3」を押し、3秒後の窓終了と停止を観察します。

ログは `.verification/issue7-physical` に保存します。実 focus、古い参照の中立、新しい接続、Aの保持とedge、終了診断を記録します。振動の物理結果は人が記録します。要求受理やログだけでは物理停止を証明できません。

Bluetooth、複数実機、他機種は別に確認してください。合成検査の手動focus呼出しと、この窓の実focusを区別してください。
