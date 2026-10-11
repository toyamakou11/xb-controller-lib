# サンプル実コードの合成試験。Unity Play と実機操作は別。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$fixture = @'
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;
using XbController;
namespace UnityEngine {
    public sealed class MinAttribute : Attribute { public MinAttribute(float value) {} }
    public enum Space { Self, World }
    public struct Vector2 { public float x, y; public Vector2(float x, float y) { this.x=x; this.y=y; } }
    public struct Vector3 {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x=x; this.y=y; this.z=z; }
        public static Vector3 operator *(Vector3 value, float scale) => new Vector3(value.x*scale,value.y*scale,value.z*scale);
    }
    public struct Quaternion {
        public Vector3 angles;
        public static Quaternion Euler(float x, float y, float z) => new Quaternion { angles=new Vector3(x,y,z) };
    }
    public class Transform {
        public Vector3 position, localEulerAngles;
        public float yaw;
        public Quaternion localRotation { set { localEulerAngles=value.angles; } }
        public void Translate(Vector3 offset, Space space) {
            double angle=space==Space.Self ? yaw*Math.PI/180 : 0;
            position.x+=(float)(offset.x*Math.Cos(angle)+offset.z*Math.Sin(angle));
            position.y+=offset.y;
            position.z+=(float)(offset.z*Math.Cos(angle)-offset.x*Math.Sin(angle));
        }
        public void Rotate(float x, float y, float z, Space space) { yaw+=y; }
    }
    public class MonoBehaviour { public readonly Transform transform=new Transform(); }
    public static class Time { public static float deltaTime=0.5f; }
    public static class Mathf {
        public static float Clamp(float value,float min,float max) => Math.Max(min,Math.Min(max,value));
        public static float Lerp(float start,float end,float amount) => start+(end-start)*Clamp(amount,0,1);
    }
    public static class Debug { public static readonly List<string> Logs=new List<string>(); public static void Log(object value) { Logs.Add(value.ToString()); } }
}
namespace XbController {
    [Flags] public enum XboxButton { A=1,B=2,X=4,Y=8,LeftShoulder=16,RightShoulder=32,RightTrigger=64 }
    public class Controller {
        public Vector2 LeftStick,RightStick;
        public float LeftTrigger,RightTrigger;
        public XboxButton Held,Pressed;
        public bool IsPressed(XboxButton button) => (Held&button)==button;
        public bool WasPressed(XboxButton button) => (Pressed&button)==button;
    }
    public static class XboxControllers { public static readonly List<Controller> All=new List<Controller>(); }
}
public static class StandardInputVerification {
    private static int assertions;
    private static readonly MethodInfo update=typeof(StandardInputExample).GetMethod("Update",BindingFlags.Instance|BindingFlags.NonPublic);
    private static void Check(bool condition,string message) { assertions++; if(!condition) throw new Exception(message); }
    private static bool Near(float actual,float expected) => Math.Abs(actual-expected)<0.001f;
    private static void Tick(StandardInputExample sample) { update.Invoke(sample,null); }
    public static int Run() {
        var sample=new StandardInputExample { view=new Transform() };
        var pad=new Controller { LeftStick=new Vector2(0,1) };
        Tick(sample);
        Check(Near(sample.transform.position.z,0),"未接続では移動しない");
        XboxControllers.All.Add(pad);
        Tick(sample);
        Check(Near(sample.transform.position.z,1.5f),"前進量は速度と時間に従う");
        sample.transform.position=default;
        sample.transform.yaw=90;
        Tick(sample);
        Check(Near(sample.transform.position.x,1.5f)&&Near(sample.transform.position.z,0),"本体の向きに沿って移動する");
        sample.transform.yaw=0;
        sample.transform.position=default;
        pad.Held=XboxButton.RightShoulder;
        Tick(sample);
        Check(Near(sample.transform.position.z,3),"RBで速度を2倍にする");
        sample.transform.position=default;
        pad.Held=XboxButton.LeftShoulder;
        Tick(sample);
        Check(Near(sample.transform.position.z,0.75f),"LBで速度を半分にする");
        sample.transform.position=default;
        pad.Held=XboxButton.LeftShoulder|XboxButton.RightShoulder;
        Tick(sample);
        Check(Near(sample.transform.position.z,1.5f),"LBとRBを相殺する");
        sample.transform.position=default;
        pad.Held=0;
        pad.LeftTrigger=0.5f;
        Tick(sample);
        Check(Near(sample.transform.position.z,1.125f),"LTの中間値で連続的に減速する");
        sample.transform.position=default;
        pad.LeftTrigger=1;
        Tick(sample);
        Check(Near(sample.transform.position.z,0.75f),"LTの最大値で速度を半分にする");
        pad.LeftStick=default;
        pad.RightStick=new Vector2(1,1);
        Tick(sample);
        Check(Near(sample.transform.yaw,60)&&Near(sample.view.localEulerAngles.x,-60),"右スティックで左右と上下を回転する");
        Tick(sample);
        Check(Near(sample.view.localEulerAngles.x,-80),"上向きの角度を制限する");
        pad.RightStick=new Vector2(0,-1);
        for(int i=0;i<4;i++) Tick(sample);
        Check(Near(sample.view.localEulerAngles.x,80),"下向きの角度を制限する");
        sample.view.localEulerAngles=new Vector3(290,0,0);
        typeof(StandardInputExample).GetMethod("OnEnable",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(sample,null);
        pad.RightStick=default;
        Tick(sample);
        Check(Near(sample.view.localEulerAngles.x,-70),"有効化時に初期角度を保持する");
        pad.Pressed=XboxButton.A|XboxButton.B|XboxButton.X|XboxButton.Y|XboxButton.RightTrigger;
        pad.RightTrigger=0.8f;
        Tick(sample);
        Check(Debug.Logs.Count==5&&Debug.Logs[0]=="A: 操作"&&Debug.Logs[1]=="B: 取消"&&Debug.Logs[2]=="X: リロード"&&Debug.Logs[3]=="Y: 切替"&&Debug.Logs[4].StartsWith("RT: 発射 強度 "),"通常ボタンとRTの操作を分ける");
        pad.Pressed=0;
        pad.Held=XboxButton.RightTrigger;
        Tick(sample);
        Check(Debug.Logs.Count==5,"RT保持で発射を重複しない");
        sample.view=null;
        pad.RightStick=new Vector2(1,1);
        Tick(sample);
        Check(Near(sample.transform.yaw,180),"Cameraなしでも左右回転する");
        XboxControllers.All.Clear();
        float yaw=sample.transform.yaw;
        Tick(sample);
        Check(Near(sample.transform.yaw,yaw)&&Debug.Logs.Count==5,"切断後は操作を止める");
        return assertions;
    }
}
'@
$source = Get-Content -LiteralPath (Join-Path $repository 'Samples~/StandardInput/StandardInputExample.cs') -Raw -Encoding utf8
Add-Type -TypeDefinition ($fixture + "`n" + $source.Replace('using UnityEngine;', '').Replace('using XbController;', ''))
'PASS assertions=' + [StandardInputVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
$sample = @($package.samples | Where-Object path -eq 'Samples~/StandardInput')
if ($sample.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $repository ($sample[0].path + '/README.md')))) {
    throw 'サンプル登録または操作手順がありません。'
}
if (@($package.dependencies.PSObject.Properties).Count -ne 1 -or $package.dependencies.'com.unity.inputsystem' -ne '1.19.0') {
    throw '依存が変更されています。'
}
'PASS サンプル登録、操作手順、既存依存'
