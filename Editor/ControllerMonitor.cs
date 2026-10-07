using System;
using UnityEditor;
using UnityEngine;

namespace XbController.Editor
{
    public sealed class ControllerMonitor : EditorWindow
    {
        private static readonly XboxButton[] buttons = (XboxButton[])Enum.GetValues(typeof(XboxButton));
        private Vector2 scroll;

        [MenuItem("Tools/Xbox Controller/入力診断")]
        public static void Open() => GetWindow<ControllerMonitor>("Xbox 入力診断");

        private void OnInspectorUpdate() => Repaint();
        private void OnGUI()
        {
            var controllers = XboxControllers.All;
            EditorGUILayout.LabelField("バックエンド", XboxControllers.Backend.ToString());
            EditorGUILayout.LabelField("初期化/更新エラー", $"0x{XboxControllers.BackendError:X8}");
            EditorGUILayout.LabelField("終了エラー", $"0x{XboxControllers.ShutdownError:X8}");
            if (XboxControllers.Backend != ControllerBackend.WindowsGameInput)
                EditorGUILayout.HelpBox("標準入力のフォールバックです。独立4パドルには Windows x64 DLL と GameInput 3.3 以降のランタイムが必要です。", MessageType.Warning);
            if (GUILayout.Button("接続を再検出")) { XboxControllers.Shutdown(); XboxControllers.Initialize(); }
            EditorGUILayout.HelpBox("Profile/Pair はゲーム入力として公開しません。Guide/Share は OS の入力方針にも依存します。", MessageType.Info);
            scroll = EditorGUILayout.BeginScrollView(scroll);
            if (controllers.Count == 0) EditorGUILayout.LabelField("接続された Gamepad がありません。");
            for (int i = 0; i < controllers.Count; i++)
            {
                var pad = controllers[i];
                EditorGUILayout.Space();
                EditorGUILayout.LabelField($"接続 {pad.ConnectionId}", EditorStyles.boldLabel);
                EditorGUILayout.LabelField("4パドルの対応情報", pad.Supports(XboxButton.Paddles) ? "公開されています（実入力の保証ではありません）" : "公開されていません");
                EditorGUILayout.LabelField("読み取りエラー", $"0x{pad.LastReadError:X8}");
                EditorGUILayout.LabelField("左 / 右スティック", $"{pad.LeftStick} / {pad.RightStick}");
                EditorGUILayout.LabelField("左 / 右トリガー", $"{pad.LeftTrigger:F3} / {pad.RightTrigger:F3}");
                foreach (var button in buttons)
                {
                    if (button == XboxButton.None || button == XboxButton.Paddles) continue;
                    EditorGUILayout.LabelField(button.ToString(), !pad.Supports(button) ? "非対応" : pad.IsPressed(button) ? "押下" : "解放");
                }
            }
            EditorGUILayout.EndScrollView();
        }
    }
}
