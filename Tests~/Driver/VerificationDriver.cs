using System;
using UnityEngine;
namespace XbController.TestDriver
{
    public sealed class VerificationDriver : MonoBehaviour
    {
        public static Action RunTest;
        private void Update()
        {
            enabled = false;
            RunTest();
        }
    }
}
