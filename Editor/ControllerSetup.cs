using UnityEditor;
using UnityEngine;

namespace XbController.Editor
{
    [InitializeOnLoad]
    public static class ControllerSetup
    {
        static ControllerSetup()
        {
            EditorApplication.delayCall += AutoSetup;
            AssemblyReloadEvents.beforeAssemblyReload += XboxControllers.Shutdown;
            EditorApplication.quitting += XboxControllers.Shutdown;
            EditorApplication.playModeStateChanged += PlayModeChanged;
        }

        private static void AutoSetup()
        {
            if (!Application.isBatchMode) EnableInput();
        }

        [MenuItem("Tools/Xbox Controller/入力を自動設定")]
        public static void EnableInput()
        {
            var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            if (assets.Length == 0) { Debug.LogError("Xbox Controller: PlayerSettings を取得できません。"); return; }
            var settings = new SerializedObject(assets[0]);
            var handler = settings.FindProperty("activeInputHandler");
            if (handler == null) { Debug.LogError("Xbox Controller: 入力設定を取得できません。"); return; }
            if (handler.intValue != 0) return;
            // Unity 契約: 0=Legacy、1=New、2=Both。
            handler.intValue = 2;
            settings.ApplyModifiedPropertiesWithoutUndo();
            AssetDatabase.SaveAssets();
            Debug.LogWarning("Xbox Controller: Active Input Handling を Both に設定しました。Unity Editor を再起動すると入力が有効になります。");
        }

        private static void PlayModeChanged(PlayModeStateChange change)
        {
            if (change == PlayModeStateChange.ExitingPlayMode || change == PlayModeStateChange.ExitingEditMode)
                XboxControllers.Shutdown();
        }
    }
}
