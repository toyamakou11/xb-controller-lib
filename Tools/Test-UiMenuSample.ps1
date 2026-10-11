[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$fixture = @'
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using XbController;
namespace UnityEngine {
    public class MinAttribute:Attribute { public MinAttribute(float value) {} }
    public class MonoBehaviour { }
    public class GameObject {
        public bool activeInHierarchy=true;
        public Selectable Selectable;
        public T GetComponent<T>() where T:class => Selectable as T;
    }
    public struct Vector2 {
        public float x,y;
        public Vector2(float x,float y) { this.x=x; this.y=y; }
        public float sqrMagnitude => x*x+y*y;
        public static Vector2 zero => default;
        public static bool operator ==(Vector2 a,Vector2 b) => a.x==b.x&&a.y==b.y;
        public static bool operator !=(Vector2 a,Vector2 b) => !(a==b);
        public override bool Equals(object value) => value is Vector2 other&&this==other;
        public override int GetHashCode() => x.GetHashCode()^y.GetHashCode();
    }
    public static class Mathf {
        public static float Abs(float value) => Math.Abs(value);
        public static float Sign(float value) => Math.Sign(value);
    }
    public static class Time { public static float unscaledTime; }
}
namespace UnityEngine.EventSystems {
    using UnityEngine;
    public interface IEventSystemHandler { }
    public interface ISubmitHandler:IEventSystemHandler { }
    public class BaseEventData { public BaseEventData(EventSystem system) {} }
    public class EventSystem {
        public static EventSystem current;
        public bool sendNavigationEvents=true,isActiveAndEnabled=true;
        public GameObject currentSelectedGameObject;
        public readonly List<GameObject> submitted=new List<GameObject>();
        public void SetSelectedGameObject(GameObject value) { currentSelectedGameObject=value; }
    }
    public delegate void EventFunction<T>(T handler,BaseEventData data) where T:IEventSystemHandler;
    public static class ExecuteEvents {
        public static readonly EventFunction<ISubmitHandler> submitHandler=(target,data)=>EventSystem.current.submitted.Add(((Button)target).gameObject);
        public static bool Execute<T>(GameObject target,BaseEventData data,EventFunction<T> handler) where T:IEventSystemHandler {
            var button=target.GetComponent<Button>();
            if (button==null) return false;
            handler((T)(IEventSystemHandler)button,data); return true;
        }
    }
}
namespace UnityEngine.UI {
    using UnityEngine;
    public class Selectable {
        public GameObject gameObject=new GameObject();
        public Selectable Up,Down,Left,Right;
        public Selectable() { gameObject.Selectable=this; }
        public Selectable FindSelectable(Vector2 direction) => direction.x<0?Left:direction.x>0?Right:direction.y<0?Down:Up;
    }
    public class Button:Selectable,ISubmitHandler { }
}
namespace XbController {
    public enum XboxButton { A,B }
    public class Controller {
        public Vector2 Dpad,LeftStick;
        public bool A,B;
        public bool WasPressed(XboxButton button) => button==XboxButton.A?A:B;
    }
    public static class XboxControllers { public static readonly List<Controller> All=new List<Controller>(); }
}
public static class UiMenuVerification {
    private static int assertions;
    private static readonly MethodInfo update=typeof(ControllerMenuExample).GetMethod("Update",BindingFlags.Instance|BindingFlags.NonPublic);
    private static void Check(bool value,string message) { assertions++; if(!value) throw new Exception(message); }
    private static void Tick(ControllerMenuExample sample) => update.Invoke(sample,null);
    public static int Run() {
        var system=new EventSystem(); EventSystem.current=system;
        var first=new Button(); var down=new Button(); var right=new Button();
        first.Down=down; first.Up=down; first.Right=right; down.Up=first; down.Right=right; right.Down=down;
        system.currentSelectedGameObject=first.gameObject;
        var cancel=new Button(); var pad=new Controller(); XboxControllers.All.Clear(); XboxControllers.All.Add(pad);
        var sample=new ControllerMenuExample { cancelButton=cancel };
        typeof(ControllerMenuExample).GetMethod("OnEnable",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(sample,null);
        Check(!system.sendNavigationEvents,"競合する EventSystem ナビゲーションを停止する");
        Time.unscaledTime=1; pad.Dpad=new Vector2(0,-1); Tick(sample);
        Check(system.currentSelectedGameObject==down.gameObject,"十字キーで即時移動する");
        pad.Dpad=default; pad.LeftStick=new Vector2(0.49f,0); Tick(sample);
        Check(system.currentSelectedGameObject==down.gameObject,"閾値未満のスティックを無視する");
        pad.Dpad=new Vector2(0,1); pad.LeftStick=new Vector2(1,0); Tick(sample);
        Check(system.currentSelectedGameObject==first.gameObject,"十字キーをスティックより優先する");
        Time.unscaledTime=1.34f; Tick(sample);
        Check(system.currentSelectedGameObject==first.gameObject,"初期遅延前に再移動しない");
        Time.unscaledTime=1.36f; Tick(sample);
        Check(system.currentSelectedGameObject==down.gameObject,"初期遅延後に長押しを繰り返す");
        Time.unscaledTime=1.40f; Tick(sample);
        Check(system.currentSelectedGameObject==down.gameObject,"繰り返し間隔内で再処理しない");
        pad.Dpad=default; pad.LeftStick=new Vector2(1,0); Time.unscaledTime=2; Tick(sample);
        Check(system.currentSelectedGameObject==right.gameObject,"閾値を超えたスティックで即時移動する");
        pad.LeftStick=default; pad.A=true; Tick(sample); pad.A=false; Tick(sample);
        Check(system.submitted.Count==1&&system.submitted[0]==right.gameObject,"A で選択中の項目を1回決定する");
        pad.B=true; Tick(sample); pad.B=false; Tick(sample);
        Check(system.submitted.Count==2&&system.submitted[1]==cancel.gameObject,"B で指定した取消項目を1回実行する");
        pad.A=pad.B=true; Tick(sample); pad.A=pad.B=false;
        Check(system.submitted.Count==3&&system.submitted[2]==right.gameObject,"同時入力で決定と取消を重複処理しない");
        sample.repeatDelay=0; sample.repeatInterval=0.01f; pad.A=pad.B=false; pad.Dpad=default; pad.LeftStick=default;
        Time.unscaledTime=3; Tick(sample); pad.Dpad=new Vector2(0,-1); Tick(sample);
        Check(system.currentSelectedGameObject==down.gameObject,"短い方向タップを直ちに処理する");
        typeof(ControllerMenuExample).GetMethod("OnDisable",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(sample,null);
        Check(system.sendNavigationEvents,"無効化時に EventSystem 設定を復元する");
        XboxControllers.All.Clear();
        return assertions;
    }
}
'@
$source = Get-Content -LiteralPath (Join-Path $repository 'Samples~/UiMenu/ControllerMenuExample.cs') -Raw -Encoding utf8
$source = $source.Replace('using UnityEngine;', '').Replace('using UnityEngine.EventSystems;', '').Replace('using UnityEngine.UI;', '').Replace('using XbController;', '')
Add-Type -TypeDefinition ($fixture + "`n" + $source)
'PASS assertions=' + [UiMenuVerification]::Run()
$package = Get-Content -LiteralPath (Join-Path $repository 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json
$sample = @($package.samples | Where-Object path -eq 'Samples~/UiMenu')
if ($sample.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $repository ($sample[0].path + '/README.md')))) {
    throw 'サンプル登録または操作手順がありません。'
}
if (@($package.dependencies.PSObject.Properties).Count -ne 1 -or $package.dependencies.'com.unity.inputsystem' -ne '1.19.0') {
    throw '依存が変更されています。'
}
'PASS サンプル登録、操作手順、既存依存'
