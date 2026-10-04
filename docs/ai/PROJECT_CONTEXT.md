# Project context

Replace TODO fields using verified repository evidence. Keep this file short; link detailed specifications instead of copying them. Do not store secrets or personal machine configuration.

- Objective: An installable Unity UPM library for standard Xbox inputs and four independent Elite Series 2 paddles.
- In scope / out of scope: Unity C# facade and Windows x64 C++ GameInput bridge; no guessed hardware mappings, no Profile/Pair game-button emulation.
- Acceptance criteria: See docs/design.md. Independent paddles require hardware evidence, not fallback success.
- Runtime and supported versions: Unity 6000.3+, Input System 1.19.0; native SDK Microsoft.GameInput 3.5.283, paddle runtime support introduced in 3.3.
- Architecture and entry points: Runtime/XboxControllers.cs and Native/bridge.cpp; Editor auto setup and diagnostics.
- Public interfaces and data invariants: Read-only controller list; supported capability separate from pressed state; invalid references read neutral; ABI v1 pack 8, 80 bytes.
- Build command: Tools/Build-Native.ps1; CMake + MSVC /W4 /WX and CTest.
- Unit / regression test command: Tools/Test-Unity.ps1 -UnityEditor '<installed Editor path>'; actual Play verification, 108 assertions passed.
- Lint / type-check command: MSVC /W4 /WX and actual Unity script compilation.
- Integration / visual verification and prerequisites: Unity 6000.3.20f1; Elite Series 2 Core tested over Bluetooth and USB-C; approved GameInput 3.5.283 runtime installed.
- Performance-sensitive paths and benchmark command: Cached public reads measured by Unity runner in 5 trials with zero managed allocations; fixture differences preclude relative speed claims.
- Dedicated test resources and data-safety constraints: .verification/ only; do not alter existing Unity projects or controller profiles; exclude SDK and local evidence from Git.
- Default branch and publication policy: main; focused codex/ branch, Japanese commits and Issue-linked PR; do not merge without authorization; no hosted CI.
- Authoritative specifications: Official Microsoft SDK header and sources linked in docs/design.md.
- Confirmed decisions: Design reviewed independently twice before code; native backend required by user's mandatory independent paddles.
- Open questions / assumptions: USB-C physical rumble at 0.25 / 700 ms confirmed by user for all four individual motors and stopping; wireless and physical lifecycle tests remain unverified. Independent paddle acceptance remains unmet: USB mapper exposes all four; raw GIP descriptor says 18 bytes but payload is empty and output metadata is absent. Receive-only Native/raw_probe.cpp rejects that mismatch. No decoder/enable command without validated protocol and hardware receipt. See docs/verification.md.

Use `Not applicable` only with a reason. Update facts when the project changes; do not turn this file into a running transcript.
