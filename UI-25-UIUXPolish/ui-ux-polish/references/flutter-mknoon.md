# Flutter and Mknoon Adapter

Load for Flutter codebases; apply the Mknoon sections only inside the identified Mknoon repository. This adapter supplies a procedure, not a claim about current files or behavior. Current `AGENTS.md`, `CLAUDE.md`, manifests, installed SDK, and project instructions take precedence. Do not load other named skills implicitly when the repository requires explicit invocation.

## 1. Discover Safely

Through `terminal`, in the verified repository workdir:

- `git status --short`
- `git branch --show-current`
- `git rev-parse HEAD`
- `flutter --version`

Use `read_file` for applicable instruction files and `pubspec.yaml`; inspect existing theme, localization, navigation, component, and test definitions via the project's indexed navigation process before editing. Do not inspect `.env` or credential files.

For a whole-app audit, reconcile routes/feature entry points with reusable UI families and live surfaces. A single search for `GestureDetector` misses controls built with buttons, semantics, native widgets, custom render objects, and shared abstractions. Start broad **navigation** with the project's architecture index, then perform anchored source verification—not unbounded raw sweeps.

Audit-only work does not authorize production edits or new repository tests. Existing focused checks and external diagnostic artifacts are allowed within scope; adding instrumentation/test code to the repo requires permission.

## 2. Mknoon Code and Document Navigation

1. Read current project instructions. Where present, use `graphify-arch/graphify-out/wiki/index.md` for broad architecture navigation.
2. Before source investigation in each branch, take an exact symbol, filename, or gate from the request, index, or current evidence and issue the compact code-only query through `terminal`:
   `python3 graphify-arch/tdd_context.py query "<ExactAnchor> <one specific implementation/caller/test relationship>" --profile general --budget 600`
3. Replace placeholders with verified anchors; do not send the literal placeholder text. Use `--profile review --budget 800` for a counterexample branch. Ask where code/test relationships live, not whether UX is good or implemented.
4. A broad/none result is discovery, not evidence. Refine once with a relevant returned anchor using `--stage refinement --refines <query_id>`, or follow current component-discovery/fallback rules.
5. Preserve `query_id`, `evidence_digest`, shortlisted production/test paths, and the open proof question. Verify claims in current source and exact assertions.
6. On a semantic branch transition, run `python3 graphify-arch/tdd_context.py checkpoint --session current --new-branch`, then the new anchored query. Follow current checkpoint cadence, browse budgets, and measured native/raw fallback instructions.
7. Before a broad multi-document search, use `python3 codex-memory/memory.py query "<focused document question>"` and inspect the returned provenance. Keep document and code exploration separate. A named plan is not code evidence or permission to invoke an execution skill.
8. If using code-exploration workers, pass the current graph context packet required by `AGENTS.md`. Parallelize independent work, not competing actions against the same app/device.

## 3. Flutter Diagnostic Candidates

These are inspection targets **only if present in the actual implementation**; trace definitions/usages before applying changes:

- **Hit regions:** `GestureDetector`, `InkWell`/`InkResponse`, padding/constraints, component tap-target density settings, nested controls, `HitTestBehavior`.
- **Layout and paint:** `Stack`, `Positioned`, transforms, ancestor bounds, clipping, `CustomPainter`/custom hit tests, render-object geometry. Compare paint position, hit position, and semantic position.
- **Input blockers:** overlays and modal barriers, `AbsorbPointer`, `IgnorePointer`, transparent/opacity layers, native view composition. Transparency alone is not proof of pointer pass-through.
- **Recognition:** tap/double-tap/long-press/drag recognizers, parent/child gesture arena, timers, slop/timeouts, pending callbacks, cancellation after disposal, actions started before recognition wins.
- **Identity and state:** stable keys, reorder/filter changes, stale closures, loading/disabled guards, route reentrancy, disposed contexts, navigation observers, async completion/error handling.
- **Accessibility:** `Semantics` and exclusions/merging, labels/roles/values/actions, focus order/restoration, custom-action availability, native semantic bridging.
- **Layout resilience:** actual SDK text-scaling API, directionality, safe areas/insets, keyboard avoidance, scroll constraints, orientation/window changes, reduced-motion settings.
- **Visual consistency:** theme/token usage, component overrides, duplicated styles, state-specific colors, long-content constraints, shared loading/error components.

Load the research reference before asserting Flutter behavior. In particular, `opaque`/`translucent` is not a universal parent/child gesture-arena fix, and changing paint clipping alone does not expand ancestor hit-test bounds. Verify installed-version behavior rather than copying the latest web API blindly.

Temporary gesture-arena/hit-area debug output can help diagnose a confirmed branch when authorized. Keep it out of release builds and redact identifiers/content in logs. Do not introduce a giant input overlay that changes the event flow being measured.

## 4. Layered Verification

Use tests at the boundary of the actual claim:

| Layer | Useful evidence | Does not prove |
|---|---|---|
| Pure unit | Layout/math/state transitions/selection/idempotency policy | Real touch geometry or user comprehension |
| Widget interaction | Real pumped layout with coordinate taps, gestures, semantics/focus, exact callback/route/destination assertions | Native OS behavior or physical ergonomics |
| Accessibility guideline | Available `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline` with semantics enabled | No occlusion/gesture conflicts, full screen-reader usability, or formal conformance |
| Golden/render review | Stable screenshot states, typography/insets/overflows/theme regression | Correct activation, navigation, or delivery |
| App integration | Production-representative wrappers, transitions, state, correct entity/outcome | Unexecuted native/device boundaries |
| Available device/emulator | Real pointer/keyboard/OS/assistive interaction and profile-mode performance as applicable | Unavailable versions or representative user-study findings |

Verify the SDK supports each referenced helper. Coordinate probes should exercise actual layout; center-only `tester.tap(finder)` tests will miss edge/overlap cases. Assert source entity and destination, not just that a callback fired.

Use bounded pumping tied to expected transitions for continuously animated screens; do not use unbounded settling or arbitrary sleeps as proof. Exercise the non-frozen animated path separately from deterministic geometry tests. Recompute positions after layout and distinguish test-fixture determinism from real-time responsiveness.

## 5. Mknoon Test Selection and Change Gates

For authorized code-changing work:

1. Read relevant `docs/testing/TESTING.md` entries and `tool/testing/selection.json` before selecting checks. Follow narrower instructions.
2. Run through `terminal`: `python3 scripts/mknoon_checks.py validate`.
3. Inspect `python3 scripts/mknoon_checks.py --help` and the relevant subcommand help. Choose an **explicit verified base revision**, preview the appropriate change selection, and run it with `--base <verified-revision>` and `--local` for working-tree changes. Do not guess undocumented subcommands, use an arbitrary base, or present a preview as a pass.
4. Add focused regression assertions and exact preservation sentinels. Review affected executable mappings if behavior/shared components/tests/configuration change; record confirmed reusable testing knowledge, not session diaries.
5. After each coherent app-owned code-change batch run `python3 graphify-arch/tdd_context.py affected <all-changed-files> --budget 600` before final QA, then run `./graphify-arch/refresh_arch_graph.sh --incremental` once for the batch. No `affected`/graph refresh for a skill-only or document-only change.
6. Run causal checks, affected curated gates, and only justified family sweeps. Do not default to full `host-all` per polish batch. Honor current wave/release cadence.
7. Run independent suites concurrently unless they contend for devices, global fixtures, generated assets, or another demonstrated resource. Record exact commands, first-attempt outcomes, reruns, and unexecuted required checks.

## 6. Device Discovery and Project-Specific Policy

### Generic Flutter device discovery

Discover at execution time through `terminal`:

- `flutter devices --machine`
- `adb devices` when Android tooling is present
- `xcrun simctl list devices available` **on macOS with Xcode** for available iOS simulators

Pin every run to an exact discovered device ID. Do not assume a connected phone, start an undiscovered emulator by invented name, or modify system accessibility settings without restoring them afterward.

Outside Mknoon, use the actual project's required target matrix and evidence policy. Do not automatically classify unavailable evidence as not applicable: an unexecuted required target may be a blocker or evidence gap, while optional targets can be explicitly deferred. Never waive a required platform claim because hardware is absent.

### Mknoon-only device policy

The following topology preference and unavailable-target exception apply **only to Mknoon**, subject to its current `AGENTS.md`.

Most local UI interactions need only one target and controlled fixtures. If a journey truly needs two peers and is not iOS-specific, use a USB-connected Android plus an available Android emulator by default; automate both from the harness. Use available iOS targets for iOS-specific or explicit parity claims, not merely as a convenient second phone. Do not ask the user to tap through an iPhone flow that the default Android pair can automate.

Unavailable hardware/version legs are `N/A (target unavailable by project policy)`, not a failure or required blocker. Missing evidence on a required **available** target remains incomplete. A blocked screen-reader tool on an available target is not the same as unavailable hardware; record the actual boundary. Host tests can preserve version-specific branches without requiring absent hardware.

## 7. Multica Tracking for Mknoon

At the start of actionable project work, use `terminal`:

- `multica --profile hermes-se issue list --output json --limit 100`
- `multica --profile hermes-se project list --output json`

If results indicate more active issues beyond the fetched page, follow the CLI's discovered pagination/filtering before deciding no duplicate exists. Reuse the active issue for the same requested outcome; otherwise create one outcome-based issue in the identified project with concise scope/acceptance, appropriate priority, and `in_progress` once work starts. Inspect CLI help before unknown write syntax.

Comment on material findings, evidence, decisions, and blockers; do not create one issue per cosmetic observation automatically. Keep audit delivery separate from implementation work. Read back the exact issue after **every** write, and read comments after comment writes. Set `blocked` for a real required dependency and `done` only for the verified requested deliverable. Do not start an agent run as an unintended status-update side effect.

If Multica is unreachable, report that tracking is blocked and continue safe independent work. Preserve the report for later linking, but never represent a local artifact as a successful board update or repeatedly retry an identical connection failure without changed conditions.
