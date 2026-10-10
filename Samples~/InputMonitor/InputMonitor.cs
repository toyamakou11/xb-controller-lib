using UnityEngine;
using XbController;

// 空の GameObject に追加する。
public sealed class InputMonitor : MonoBehaviour
{
    /// <summary>
    /// Reports A-button press events with their connection IDs in the Unity console,
    /// initializing the controller facade on first access if needed.
    /// </summary>
    private void Update()
    {
        var pads = XboxControllers.All;
        for (int i = 0; i < pads.Count; i++)
        {
            var pad = pads[i];
            if (pad.WasPressed(XboxButton.A)) Debug.Log($"接続 {pad.ConnectionId}: A");
        }
    }
}
