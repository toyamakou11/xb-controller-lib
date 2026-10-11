using UnityEngine;
using XbController;

public sealed class RumbleExample : MonoBehaviour
{
    [Range(0, 1)] public float intensity = 0.25f;
    [Min(0.01f)] public float duration = 0.7f;
    private Controller activePad;
    private double stopAt;
    private string result = "未要求";

    public bool Play(float low, float high, float leftTrigger, float rightTrigger, float seconds)
    {
        if (!isActiveAndEnabled || !XboxControllers.HasFocus || float.IsNaN(seconds) ||
            float.IsInfinity(seconds) || seconds <= 0) return false;
        var pads = XboxControllers.All;
        if (pads.Count == 0) return false;
        var pad = pads[0];
        if (!pad.SetRumble(low, high, leftTrigger, rightTrigger)) return false;
        if (activePad != pad) Stop();
        activePad = pad;
        stopAt = Time.unscaledTimeAsDouble + seconds;
        return true;
    }

    public void Stop()
    {
        if (activePad == null) return;
        activePad.SetRumble(0, 0, 0, 0);
        activePad = null;
    }

    private void Update()
    {
        if (activePad != null && (!activePad.IsConnected || !XboxControllers.HasFocus ||
            Time.unscaledTimeAsDouble >= stopAt)) Stop();
    }

    private void OnDisable() => Stop();
    private void OnApplicationQuit() => Stop();
    private void OnApplicationFocus(bool focused) { if (!focused) Stop(); }

    private void Request(float low, float high, float leftTrigger, float rightTrigger)
    {
        result = Play(low, high, leftTrigger, rightTrigger, duration) ? "API 受付" : "API 拒否";
    }

    private void OnGUI()
    {
        var pads = XboxControllers.All;
        uint motors = pads.Count == 0 ? 0 : pads[0].SupportedRumbleMotors;
        GUILayout.BeginArea(new Rect(10, 10, 340, 300), GUI.skin.box);
        GUILayout.Label($"先頭の接続: 対応マスク 0x{motors:X}");
        GUILayout.Label($"強度 {intensity:0.00} / 時間 {duration:0.00} 秒");
        if (GUILayout.Button("本体低周波")) Request(intensity, 0, 0, 0);
        if (GUILayout.Button("本体高周波")) Request(0, intensity, 0, 0);
        if (GUILayout.Button("左トリガー")) Request(0, 0, intensity, 0);
        if (GUILayout.Button("右トリガー")) Request(0, 0, 0, intensity);
        if (GUILayout.Button("対応モーターを同時に要求"))
            Request((motors & 1) != 0 ? intensity : 0, (motors & 2) != 0 ? intensity : 0,
                (motors & 4) != 0 ? intensity : 0, (motors & 8) != 0 ? intensity : 0);
        if (GUILayout.Button("停止")) { Stop(); result = "停止要求"; }
        GUILayout.Label(result + "。物理応答は別途確認。");
        GUILayout.EndArea();
    }
}
