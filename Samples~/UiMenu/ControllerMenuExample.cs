using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using XbController;

public sealed class ControllerMenuExample : MonoBehaviour
{
    public Button cancelButton;
    [Min(0)] public float repeatDelay = 0.35f;
    [Min(0.01f)] public float repeatInterval = 0.12f;
    [Min(0)] public float stickThreshold = 0.5f;

    private EventSystem eventSystem;
    private bool previousNavigationEvents;
    private Vector2 heldDirection;
    private float nextRepeatTime;

    private void OnEnable()
    {
        eventSystem = EventSystem.current;
        if (eventSystem == null) return;
        previousNavigationEvents = eventSystem.sendNavigationEvents;
        eventSystem.sendNavigationEvents = false;
    }

    private void OnDisable()
    {
        if (eventSystem != null) eventSystem.sendNavigationEvents = previousNavigationEvents;
        heldDirection = Vector2.zero;
    }

    private void Update()
    {
        if (eventSystem == null || !eventSystem.isActiveAndEnabled) { ResetRepeat(); return; }
        var pads = XboxControllers.All;
        if (pads.Count == 0) { ResetRepeat(); return; }

        var pad = pads[0];
        Vector2 direction = ReadDirection(pad.Dpad, pad.LeftStick);
        MoveSelection(direction);

        if (pad.WasPressed(XboxButton.A)) Submit(eventSystem.currentSelectedGameObject);
        else if (pad.WasPressed(XboxButton.B) && cancelButton != null) Submit(cancelButton.gameObject);
    }

    private Vector2 ReadDirection(Vector2 dpad, Vector2 stick)
    {
        if (dpad.sqrMagnitude > 0) return Cardinal(dpad);
        if (stick.sqrMagnitude < stickThreshold * stickThreshold) return Vector2.zero;
        return Cardinal(stick);
    }

    private static Vector2 Cardinal(Vector2 value)
    {
        if (Mathf.Abs(value.x) > Mathf.Abs(value.y)) return new Vector2(Mathf.Sign(value.x), 0);
        if (Mathf.Abs(value.y) > 0) return new Vector2(0, Mathf.Sign(value.y));
        return Vector2.zero;
    }

    private void MoveSelection(Vector2 direction)
    {
        if (direction == Vector2.zero) { ResetRepeat(); return; }
        if (direction != heldDirection)
        {
            heldDirection = direction;
            SelectNext(direction);
            nextRepeatTime = Time.unscaledTime + repeatDelay;
            return;
        }
        if (Time.unscaledTime < nextRepeatTime) return;
        SelectNext(direction);
        nextRepeatTime = Time.unscaledTime + repeatInterval;
    }

    private void SelectNext(Vector2 direction)
    {
        var current = eventSystem.currentSelectedGameObject;
        var selectable = current != null ? current.GetComponent<Selectable>() : null;
        var next = selectable != null ? selectable.FindSelectable(direction) : null;
        if (next != null) eventSystem.SetSelectedGameObject(next.gameObject);
    }

    private void Submit(GameObject target)
    {
        if (target == null || !target.activeInHierarchy) return;
        ExecuteEvents.Execute(target, new BaseEventData(eventSystem), ExecuteEvents.submitHandler);
    }

    private void ResetRepeat()
    {
        heldDirection = Vector2.zero;
        nextRepeatTime = 0;
    }
}
