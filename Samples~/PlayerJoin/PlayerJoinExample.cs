using System;
using UnityEngine;
using XbController;

public sealed class PlayerJoinExample : MonoBehaviour
{
    public Transform[] players = new Transform[2];
    [Min(0)] public float moveSpeed = 3;
    private Controller[] assignments = Array.Empty<Controller>();

    private void OnEnable() => assignments = new Controller[players?.Length ?? 0];
    private void OnDisable() => assignments = Array.Empty<Controller>();

    public Controller GetController(int player)
    {
        if (player < 0 || player >= assignments.Length) return null;
        var pad = assignments[player];
        return pad != null && pad.IsConnected ? pad : null;
    }

    private void Update()
    {
        int count = players?.Length ?? 0;
        if (assignments.Length != count) OnEnable();
        if (count == 0) return;
        for (int i = 0; i < count; i++)
            if (assignments[i] != null && !assignments[i].IsConnected) assignments[i] = null;

        foreach (var pad in XboxControllers.All)
        {
            if (!pad.WasPressed(XboxButton.A) || Array.IndexOf(assignments, pad) >= 0) continue;
            for (int i = 0; i < count; i++) if (assignments[i] == null)
            {
                assignments[i] = pad;
                Debug.Log($"プレイヤー {i + 1}: 参加");
                break;
            }
        }

        for (int i = 0; i < count; i++)
        {
            var pad = GetController(i);
            if (pad == null) continue;
            Vector2 move = pad.LeftStick;
            if (players[i] != null)
                players[i].Translate(new Vector3(move.x, 0, move.y) * moveSpeed * Time.deltaTime, Space.World);
            if (pad.WasPressed(XboxButton.B)) Debug.Log($"プレイヤー {i + 1}: B");
        }
    }
}
