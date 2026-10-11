using System;
using System.IO;
using UnityEngine;
using UnityEngine.InputSystem;
using XbController;

public sealed class PhysicalVerification : MonoBehaviour
{
    private Controller pad, lastPad;
    private string status = "USB-Cで1台を接続してください。";
    private string log;
    private float stopAt;
    private bool reconnect;
    private bool observeReconnectA;
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Create() => new GameObject("実機検証").AddComponent<PhysicalVerification>();
    private void Start()
    {
        Application.runInBackground = true;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        string[] args = Environment.GetCommandLineArgs();
        int index = Array.IndexOf(args, "-evidence");
        if (index < 0 || index + 1 >= args.Length) { enabled = false; Application.Quit(1); return; }
        log = args[index + 1];
        Application.focusChanged += Focus;
        Application.quitting += Quit;
        Record("開始 backend=" + XboxControllers.Backend);
    }
    private void Record(string message)
    {
        status = message;
        File.AppendAllText(log, DateTime.UtcNow.ToString("O") + " " + message + "\n");
        Debug.Log(message);
    }
    private void Focus(bool focused)
    {
        Record($"実focus={focused} libraryFocus={XboxControllers.HasFocus} A={pad?.IsPressed(XboxButton.A)} edge={pad?.WasPressed(XboxButton.A)}");
    }
    private void Quit() => Record($"終了 stale={lastPad != null && !lastPad.IsConnected} shutdown=0x{XboxControllers.ShutdownError:X8}");
    private void Update()
    {
        var all = XboxControllers.All;
        pad = all.Count == 1 ? all[0] : null;
        if (pad != null && !ReferenceEquals(pad, lastPad))
        {
            Record($"接続 token={pad.ConnectionId} A={pad.IsPressed(XboxButton.A)} pressed={pad.WasPressed(XboxButton.A)} released={pad.WasReleased(XboxButton.A)} reconnect={reconnect}");
            lastPad = pad;
            observeReconnectA = reconnect;
        }
        if (observeReconnectA && pad != null && pad.IsPressed(XboxButton.A))
        {
            Record($"再接続のA held=True pressed={pad.WasPressed(XboxButton.A)} released={pad.WasReleased(XboxButton.A)}");
            observeReconnectA = false;
        }
        if (reconnect && lastPad != null && !lastPad.IsConnected && pad == null)
        {
            Record($"切断 connected={lastPad.IsConnected} neutral={lastPad.LeftStick == Vector2.zero && !lastPad.IsPressed(XboxButton.A)}");
            lastPad = null;
        }
        if (stopAt > 0 && Time.realtimeSinceStartup >= stopAt)
        {
            pad?.StopRumble();
            stopAt = 0;
            Record("60秒の安全停止");
        }
    }
    private bool Rumble(string name)
    {
        if (!Application.isFocused || pad == null || XboxControllers.Backend != ControllerBackend.WindowsGameInput)
        {
            Record("GameInputの1台とウィンドウfocusが必要です。"); return false;
        }
        bool accepted = pad.SetRumble(0.25f, 0.25f);
        stopAt = accepted ? Time.realtimeSinceStartup + 60 : 0;
        Record(name + " accepted=" + accepted);
        return accepted;
    }
    private void OnGUI()
    {
        GUI.skin.label.fontSize = GUI.skin.button.fontSize = 18;
        GUILayout.BeginArea(new Rect(20, 20, 740, 460));
        GUILayout.Label("USB-C 実機検証");
        GUILayout.Label($"backend={XboxControllers.Backend} devices={XboxControllers.All.Count} focus={Application.isFocused}");
        GUILayout.Label("1: 振動開始後、別の窓をクリック。停止後に戻り、自動再開がないか確認。");
        if (GUILayout.Button("1 フォーカス試験: 振動開始", GUILayout.Height(48))) Rumble("focus試験");
        GUILayout.Label("2: 振動開始後、USB-Cを外す。Aを保持して接続し、再開がないか確認。");
        if (GUILayout.Button("2 切断試験: 振動開始", GUILayout.Height(48))) { reconnect = true; Rumble("切断試験"); }
        GUILayout.Label("3: 振動開始から3秒で終了。終了時の停止を確認。");
        if (GUILayout.Button("3 終了試験: 振動開始", GUILayout.Height(48)) && Rumble("終了試験")) Invoke(nameof(Exit), 3);
        if (GUILayout.Button("停止", GUILayout.Height(36))) { pad?.StopRumble(); stopAt = 0; Record("明示停止"); }
        GUILayout.Label(status);
        GUILayout.EndArea();
    }
    private void Exit() => Application.Quit();
}
