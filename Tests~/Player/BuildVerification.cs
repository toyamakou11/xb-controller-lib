using System;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;

public static class BuildVerification
{
    public static void Build()
    {
        XbController.Editor.ControllerSetup.EnableInput();
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.IL2CPP);
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene);
        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene(), "Assets/Verification.unity");
        string[] args = Environment.GetCommandLineArgs();
        int outputIndex = Array.IndexOf(args, "-player-output");
        if (outputIndex < 0 || outputIndex + 1 >= args.Length || args[outputIndex + 1].StartsWith("-"))
            throw new ArgumentException("-player-output と出力先が必要です。");
        var result = BuildPipeline.BuildPlayer(new BuildPlayerOptions {
            scenes = new[] { "Assets/Verification.unity" },
            locationPathName = args[outputIndex + 1],
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.Development
        });
        if (result.summary.result != BuildResult.Succeeded) throw new Exception("IL2CPPビルド失敗 " + result.summary.result);
    }
}
