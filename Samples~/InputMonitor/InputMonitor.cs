using UnityEngine;
using XbController;

// 空の GameObject に追加する。
public sealed class InputMonitor : MonoBehaviour
{
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
