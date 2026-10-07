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
            if (pad.WasPressed(XboxButton.PaddleLeft1)) Debug.Log($"接続 {pad.ConnectionId}: 左パドル1");
            if (pad.WasPressed(XboxButton.PaddleLeft2)) Debug.Log($"接続 {pad.ConnectionId}: 左パドル2");
            if (pad.WasPressed(XboxButton.PaddleRight1)) Debug.Log($"接続 {pad.ConnectionId}: 右パドル1");
            if (pad.WasPressed(XboxButton.PaddleRight2)) Debug.Log($"接続 {pad.ConnectionId}: 右パドル2");
        }
    }
}
