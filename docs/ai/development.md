# Development overlay

Inherit the global workflow and efficiency rules. Load this file only for development.

- Establish the repository root, branch, relevant instructions, affected entry points, runtime, and verification commands. Preserve uncommitted user changes.
- Trace affected behavior and contracts. Design the smallest adequate change; evaluate failure cases, compatibility, security, maintenance, and performance. Obtain independent design review for consequential changes when available.
- Prefer existing architecture and native tools. Add abstractions or dependencies only for demonstrated needs. Delegate disjoint implementation after agreeing interfaces and ownership; serialize integration.
- Add regression tests for meaningful behavior changes. For low-impact reversible edits, use focused checks instead of implementation-mirroring tests. Run required gates and integration or visual checks relevant to actual behavior.
- If debugging stalls, retain evidence and seek an independent reassessment instead of blind retries. Benchmark performance-sensitive changes with comparable inputs, repetitions, environment, and correctness evidence.
- Independently review the final diff when useful; fix actionable findings and rerun affected checks. Never repeat unchanged full suites without a reason.
- When publication is authorized: link or create an Issue, use a focused branch and small Japanese commits, push without force, open a Japanese PR describing behavior and verification, and review the published head. Recheck after fixes. Merge only when authorized.
- Do not enable hosted CI or paid services without explicit permission. Exclude credentials, personal settings, generated evidence, and unrelated changes from commits.
