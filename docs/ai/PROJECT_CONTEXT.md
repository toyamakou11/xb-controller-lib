# Project context

Replace TODO fields using verified repository evidence. Keep this file short; link detailed specifications instead of copying them. Do not store secrets or personal machine configuration.

- Objective: An installable Unity UPM library for standard Xbox inputs and four independent Elite Series 2 paddles.
- In scope / out of scope: Unity C# facade and Windows x64 C++ GameInput bridge; no guessed hardware mappings, no Profile/Pair game-button emulation.
- Acceptance criteria: See docs/design.md. Independent paddles require hardware evidence, not fallback success.
- Runtime and supported versions: Unity 6000.3+, Input System 1.19.0; native SDK Microsoft.GameInput 3.5.283, paddle runtime support introduced in 3.3.
- Architecture and entry points: Runtime/XboxControllers.cs, Native/bridge.cpp, and Native/gatt_paddles.cpp; C++20 WinRT GATT supplement with exact ContainerId binding; Editor auto setup and diagnostics.
- Public interfaces and data invariants: Read-only controller list; supported capability separate from pressed state; invalid references read neutral; ABI v1 pack 8, 80 bytes.
- Build command: Tools/Build-Native.ps1; CMake + MSVC /W4 /WX and CTest.
- Unit / regression test command: Tools/Test-NativePolling.ps1 (10 synthetic assertions); Tools/Test-Unity.ps1 -UnityEditor '<installed Editor path>' (prior actual Play: 108 assertions; 2026-10-08 retry blocked by Editor license, actual Unity-reference runtime compilation passed).
- Lint / type-check command: MSVC /W4 /WX and actual Unity script compilation.
- Integration / visual verification and prerequisites: Unity 6000.3.20f1; Elite Series 2 Core tested over Bluetooth and USB-C; approved GameInput 3.5.283 runtime installed.
- Performance-sensitive paths and benchmark command: Cached public reads measured by Unity runner in 5 trials with zero managed allocations; fixture differences preclude relative speed claims.
- Dedicated test resources and data-safety constraints: .verification/ only; do not alter existing Unity projects or controller profiles; exclude SDK and local evidence from Git.
- Default branch and publication policy: main; focused codex/ branch, Japanese commits and Issue-linked PR; do not merge without authorization; no hosted CI.
- Authoritative specifications: Official Microsoft SDK header and sources linked in docs/design.md.
- Confirmed decisions: Independent design and implementation reviews; Bluetooth vendor GATT physically receives four independent paddles (5.23.6.0/profile 1), individual/simultaneous press-release, ABXY independence; native ABI remains 80 bytes. No service-memory offsets, ABXY inference, firmware whitelist, or downgrade.
- Open questions / assumptions: USB-C rumble at 0.25 / 700 ms confirmed for all four individual motors and stopping. USB independent paddles remain unavailable through public GameInput (18-byte descriptor, empty payload, no output metadata). Physical lifecycle and other firmware/transport results must remain distinct from synthetic tests. See docs/verification.md.

Use `Not applicable` only with a reason. Update facts when the project changes; do not turn this file into a running transcript.
