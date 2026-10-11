# Project context

- Objective: Build an installable Unity UPM wrapper for standard controller input and rumble.
- Scope: Reuse Unity Input System and GameInput. Treat remapped paddles as ordinary assigned buttons.
- Exclusions: Independent paddle input, vendor GATT, USB raw reports, WGI helpers, Xbox Wireless Adapter support and validation, driver changes, and automatic controller profile changes.
- Acceptance criteria: See docs/design.md. Independent paddle detection is not a completion requirement.
- Versions: Unity 6000.3+, Input System 1.19.0, Microsoft.GameInput SDK 3.5.283, and GameInput v3 runtime for the Windows backend.
- Architecture: C# facade; Unity Gamepad backend; Windows x64 C++17 GameInput bridge for input history and four-motor rumble.
- Entry points: Runtime/XboxControllers.cs, Runtime/Controller.cs, Native/bridge.cpp, and Editor/ControllerSetup.cs.
- Contracts: Main-thread access, read-only device list, neutral stale references, owned-rumble stopping, ABI v1, and 80-byte snapshots.
- Migration: Version 0.2.0 removes paddle-specific enum members. Standard button values and rumble APIs remain unchanged.
- Checks: Tools/Build-Native.ps1, Tools/Test-NativePolling.ps1, and Tools/Test-Unity.ps1 with an installed Editor path.
- Evidence: See docs/verification.md for current checks. Preserve earlier hardware and research results in docs/archive/verification-20261010.md.
- Constraints: Do not install runtimes silently, alter existing Unity projects, or use GitHub Actions.
- Test resources: Use .verification/ and the dedicated temporary Unity verification project.
- Publication: Use focused codex/ branches and Japanese Issue-linked PRs. Merge requires authorization.
- Open checks: IL2CPP Player, multiple physical devices, other transports, and physical focus-loss and disconnect rumble stopping.

Do not promote optional backend features into requirements without an explicit user request.
