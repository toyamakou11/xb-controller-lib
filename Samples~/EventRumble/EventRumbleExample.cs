using UnityEngine;
using XbController;

public sealed class EventRumbleExample : MonoBehaviour
{
    public RumbleExample rumble;
    private RumbleExample activeRumble;
    private string result = "未要求";

    public bool Fire() => Request(0.1f, 0.15f, 0, 0.4f, 0.08f);
    public bool Recoil() => Request(0.3f, 0.2f, 0, 0.6f, 0.15f);
    public bool Hit() => Request(0.7f, 0.4f, 0.3f, 0.3f, 0.35f);

    private bool Request(float low, float high, float left, float right, float seconds)
    {
        if (!isActiveAndEnabled || rumble == null || !XboxControllers.HasFocus) return false;
        var pads = XboxControllers.All;
        uint motors = pads.Count == 0 ? 0 : pads[0].SupportedRumbleMotors;
        low = (motors & 1) != 0 ? low : 0;
        high = (motors & 2) != 0 ? high : 0;
        left = (motors & 4) != 0 ? left : 0;
        right = (motors & 8) != 0 ? right : 0;
        if (low + high + left + right == 0) return false;
        if (activeRumble != rumble) Stop();
        if (!rumble.Play(low, high, left, right, seconds)) return false;
        activeRumble = rumble;
        return true;
    }

    public void Stop()
    {
        if (activeRumble != null) activeRumble.Stop();
        activeRumble = null;
    }

    private void OnDisable() => Stop();
    private void OnApplicationQuit() => Stop();

    private void OnGUI()
    {
        GUILayout.BeginArea(new Rect(360, 10, 300, 180), GUI.skin.box);
        if (GUILayout.Button("発射")) result = Fire() ? "API 受付" : "API 拒否";
        if (GUILayout.Button("反動")) result = Recoil() ? "API 受付" : "API 拒否";
        if (GUILayout.Button("被弾")) result = Hit() ? "API 受付" : "API 拒否";
        if (GUILayout.Button("効果を停止")) { Stop(); result = "停止要求"; }
        GUILayout.Label(result + "。物理応答は別途確認。");
        GUILayout.EndArea();
    }
}
