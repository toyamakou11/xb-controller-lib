using UnityEngine;
using XbController;

public sealed class StandardInputExample : MonoBehaviour
{
    public Transform view;
    [Min(0)] public float moveSpeed = 3;
    [Min(0)] public float lookSpeed = 120;
    private float pitch;

    private void OnEnable()
    {
        float angle = view != null ? view.localEulerAngles.x : 0;
        pitch = Mathf.Clamp(angle > 180 ? angle - 360 : angle, -80, 80);
    }

    private void Update()
    {
        var pads = XboxControllers.All;
        if (pads.Count == 0) return;
        var pad = pads[0];
        float speed = moveSpeed;
        if (pad.IsPressed(XboxButton.LeftShoulder)) speed *= 0.5f;
        if (pad.IsPressed(XboxButton.RightShoulder)) speed *= 2;
        speed *= Mathf.Lerp(1, 0.5f, pad.LeftTrigger);

        Vector2 move = pad.LeftStick;
        transform.Translate(new Vector3(move.x, 0, move.y) * speed * Time.deltaTime, Space.Self);
        Vector2 look = pad.RightStick;
        transform.Rotate(0, look.x * lookSpeed * Time.deltaTime, 0, Space.World);
        if (view != null)
        {
            pitch = Mathf.Clamp(pitch - look.y * lookSpeed * Time.deltaTime, -80, 80);
            view.localRotation = Quaternion.Euler(pitch, 0, 0);
        }

        if (pad.WasPressed(XboxButton.A)) Debug.Log("A: 操作");
        if (pad.WasPressed(XboxButton.B)) Debug.Log("B: 取消");
        if (pad.WasPressed(XboxButton.X)) Debug.Log("X: リロード");
        if (pad.WasPressed(XboxButton.Y)) Debug.Log("Y: 切替");
        if (pad.WasPressed(XboxButton.RightTrigger)) Debug.Log($"RT: 発射 強度 {pad.RightTrigger:F2}");
    }
}
