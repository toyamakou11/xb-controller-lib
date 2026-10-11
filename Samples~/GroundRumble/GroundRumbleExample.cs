using UnityEngine;
using XbController;

public enum GroundSurface { Smooth, Rough }

public sealed class GroundRumbleExample : MonoBehaviour
{
    public RumbleExample rumble;
    private RumbleExample activeRumble;

    public bool ApplyGround(bool grounded, float speed, GroundSurface surface)
    {
        if (!isActiveAndEnabled || rumble == null || !grounded || speed <= 0 ||
            float.IsNaN(speed) || float.IsInfinity(speed)) { Stop(); return false; }
        var pads = XboxControllers.All;
        uint motors = pads.Count == 0 ? 0 : pads[0].SupportedRumbleMotors;
        if ((motors & 15) == 0) { Stop(); return false; }
        float level = Mathf.Clamp01(speed / 6) * (surface == GroundSurface.Rough ? 0.4f : 0.1f);
        if (activeRumble != rumble) Stop();
        bool accepted = rumble.Play((motors & 1) != 0 ? level : 0, (motors & 2) != 0 ? level * 0.5f : 0,
            (motors & 4) != 0 ? level * 0.25f : 0, (motors & 8) != 0 ? level * 0.25f : 0, 0.1f);
        if (!accepted) { Stop(); return false; }
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
}
