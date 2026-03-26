# Session 15 Plan: Profile Orbit Painter Cost And Optimize Only If Hot

**Date:** 2026-03-26
**Status:** Plan only

## 1. Real Scope

Confirm whether Orbit painter work is actually hot on real route open / close flows before touching rendering code.

This session is not allowed to optimize from inspection alone. The current code shows repeated dashed-arc math in:
- `OrbitalRingPainter.paint()`
- `_DashedBorderPainter.paint()`

But both painters also return `shouldRepaint => false`, so the real question is not "do these loops exist?" It is:
- do they appear on the paint / raster hot path during Orbit route open or close
- does the delayed `OverflowBadge` animation materially change that cost
- is the dominant cost the dash math itself, the `BackdropFilter`, or something else in the route

Out of scope:
- Orbit redesign or visual restyling
- speculative painter caching with no trace evidence
- broad `OrbitWired` state refactors unless profiling unexpectedly shows build churn is the dominant issue
- unrelated feed, conversation, startup, or transport performance work

## 2. Session Classification

`profile-gated`

Why:
- `Test-Flight-Improv/04-ui-performance.md` marks Orbit painters as a profile-gated medium-severity candidate, not a confirmed regression
- code inspection alone cannot answer whether the paint work is actually hot
- the current tree has Orbit behavior/widget tests but no Orbit-specific route-open / route-close perf harness

## 3. Files and Repos to Inspect Next

Primary planning and perf context:
- `Test-Flight-Improv/16-session-todo-roadmap-2.md`
- `Test-Flight-Improv/04-ui-performance.md`

Primary Orbit code path:
- `lib/features/orbit/presentation/navigation/orbit_route_transition.dart`
- `lib/features/orbit/presentation/widgets/orbital_ring_painter.dart`
- `lib/features/orbit/presentation/widgets/overflow_badge.dart`
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/main.dart`

Existing tests to reuse:
- `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
- `test/features/orbit/presentation/widgets/overflow_badge_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

Reference perf harness patterns:
- `integration_test/feed_performance_test.dart`
- `integration_test/identity_progress_performance_test.dart`

## 4. Existing Tests Covering This Area

Current useful coverage:
- `orbital_visualization_test.dart` proves the rings, avatars, and overflow badge render in the expected widget tree
- `overflow_badge_test.dart` proves the delayed badge animation and `BackdropFilter` are present
- `orbit_wired_test.dart` proves route behavior and already exposes `debugOnHeaderBuild` / `debugOnListBuild` hooks that can help rule out build churn
- `feed_performance_test.dart` and `identity_progress_performance_test.dart` show existing repo patterns for `IntegrationTestWidgetsFlutterBinding`, `FrameTiming` collection, and device-backed validation

What is still missing:
- no Orbit-specific integration perf harness
- no route-open / route-close trace for Orbit
- no existing evidence showing whether `OrbitalRingPainter` or `_DashedBorderPainter` appear in the paint / raster hot path
- no existing Orbit perf harness explicitly bound to the production `buildOrbitSlideUpRoute(...)` transition

## 5. Regression / Tests To Add First

Default answer: none.

If Session 15 stays measurement-only, do not add tests first.

If profiling justifies an optimization, add the smallest protective test at the layer actually touched:
- if ring painter caching or paint semantics change, extend `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`
- if badge animation / blur / badge painter behavior changes, extend `test/features/orbit/presentation/widgets/overflow_badge_test.dart`
- only add a broader `orbit_wired` test if the optimization actually changes route-level build or animation behavior

## 6. Evidence To Capture First

Capture these before any production edit:
- profile-mode Orbit route-open trace on one representative device
- profile-mode Orbit route-close trace on the same device
- route-open / route-close measurements through the real `buildOrbitSlideUpRoute(...)` transition, not a synthetic direct mount
- one scenario with `overflowCount == 0`
- one scenario with `overflowCount > 0` so the delayed `OverflowBadge` entrance occurs after 1000ms
- Flutter frames chart plus Performance timeline for the same runs
- whether `OrbitalRingPainter` or `_DashedBorderPainter` appear on the hot path during paint / raster spikes
- whether `BackdropFilter` blur or the delayed badge animation is a bigger contributor than dashed-arc math
- optional secondary evidence from `debugOnHeaderBuild` / `debugOnListBuild` to show whether the issue is paint-bound versus rebuild-bound

## 7. Step-by-Step Implementation Or Evidence-Collection Plan

1. Confirm the target flow and device class.
2. Prefer a physical iPhone for mobile-representative profiling when available; Flutter profile builds are not supported for iOS simulators in this environment, so use `macos` as the fallback engine-backed profile target.
3. Inspect the real Orbit entry points in `feed_wired.dart` and `main.dart`, and bind the harness to `buildOrbitSlideUpRoute(...)` from `orbit_route_transition.dart` so route-open / route-close cost matches production.
4. Create a temporary local Orbit profile harness, modeled on `integration_test/feed_performance_test.dart` and `integration_test/identity_progress_performance_test.dart`, because no Orbit-specific perf harness exists today.
5. Prefer a smaller `OrbitScreen`-style harness, following the notifier-driven patterns already used in `orbit_screen_loading_test.dart` and `orbit_screen_archived_groups_test.dart`; only escalate to a fuller `OrbitWired` harness if the smaller route-driven harness cannot reproduce the badge/build behavior needed for the trace.
6. Use that temporary harness to make two deterministic scenarios easy to replay:
   - Orbit open / close with no overflow badge
   - Orbit open / idle / close with `friends.length > 13` so the delayed badge animation and `_DashedBorderPainter` are exercised
7. Run a profile-mode capture command on the same device for all before traces:

```bash
flutter devices
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/orbit_performance_test.dart -d <device-id> --profile
```

8. Open DevTools for that profile run and capture:
   - Performance timeline
   - Flutter frames chart
   - route-open and route-close windows
   - the delayed badge-entrance window
9. Answer the hot-path question explicitly:
   - if the painters do not show up materially, stop and record that Session 15 is profiling-only with no optimization
   - if they do show up materially, rank the dominant cause first: dash math, blur, animation, or broader build/layout churn
10. Only then choose the narrowest optimization and add the smallest matching regression test first.
11. Re-run the same harness and the same device flow for before/after comparison if code changed.

Why a temporary harness is required:
- existing Orbit tests are widget/behavior tests, not engine-backed route traces
- the feed and identity perf tests provide the pattern, but not an Orbit scenario
- the harness must drive the production route helper, not just mount `OrbitScreen` directly
- `FrameTiming` alone does not identify the specific painter hot path, so the harness must be paired with a real profile trace

## 8. Risks And Edge Cases

- `shouldRepaint => false` lowers steady repaint churn, so the painter loops may look suspicious in code while still being irrelevant in traces.
- `OverflowBadge` cost may come more from `BackdropFilter` blur and delayed animation than from `_DashedBorderPainter`.
- `OrbitalAvatar` entrance animations and route collapse animation can overlap the same trace window, so the session must isolate route-open, badge-delay, and route-close windows instead of mixing them.
- A full `OrbitWired` harness can pull in unrelated state/build churn, so the first measurement pass should stay on the smaller `OrbitScreen`-style route harness unless traces prove that is insufficient.
- `debugOnHeaderBuild` and `debugOnListBuild` can help rule out rebuild churn, but they do not prove raster or paint cost by themselves.
- If physical iPhone profiling is unavailable, `macos` is the acceptable fallback engine-backed profile target, but before/after comparisons must still use the same device and same flow.
- Dependency impact if Session 15 blocks: Sessions 16 and 17 can still proceed independently, but the Orbit painter question stays unresolved and must not be converted into speculative cleanup later.

## 9. Exact Tests To Run After Implementation

If no production code changes occur:

```bash
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart
flutter test test/features/orbit/presentation/widgets/overflow_badge_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/orbit_performance_test.dart -d <device-id> --profile
```

If production code changes occur:

```bash
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart
flutter test test/features/orbit/presentation/widgets/overflow_badge_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/orbit_performance_test.dart -d <device-id> --profile
./scripts/run_test_gates.sh baseline
```

If the temporary local harness stays outside committed repo changes, still record the exact trace-capture command and device used.

## 10. Subsystem Gate(s)

No named subsystem gate by default.

Reason:
- Session 15 is a profiling decision point, not a feature-area contract change
- there is no Orbit-specific named gate in the current gate definitions

## 11. Whether Baseline Gate Is Required

Optional / not required for pure profiling.

Required if any production Orbit code changes.

Reason:
- the roadmap explicitly marks Baseline Gate as optional for profiling-only work and required once production code changes land

## 12. Whether Startup / Transport Gate Is Required

No.

Reason:
- this session is about Orbit painter cost during route transitions
- it does not touch startup, reconnect, transport fallback, or bridge behavior

## 13. Done Criteria

Session 15 is complete when one of these is true:
- profile traces show that the Orbit painters are not materially on the hot path, and the session ends with evidence only
- or profile traces show that one of these painters is materially hot, a narrow optimization lands, and before/after evidence confirms the improvement

And all of these are true:
- the session produces a clear answer to whether `OrbitalRingPainter` or `_DashedBorderPainter` deserve optimization
- the answer distinguishes paint/raster cost from broader rebuild churn
- the answer is based on the production Orbit route transition rather than a synthetic direct mount
- no speculative cleanup lands without trace evidence
- any optimization remains narrowly scoped and protected by the smallest relevant test

## 14. Dependency Impact On Later Sessions If This Session Blocks

- Session 16 and Session 17 remain independent and can still proceed if Session 15 stays unresolved.
- A Session 15 block should not force speculative Orbit painter cleanup into later sessions; later work must continue to treat the painter question as unresolved until profile evidence exists.
- Later DB- or conversation-focused sessions are unaffected by this Orbit profiling work.

## 15. Scope Guard

- Do not redesign the Orbit UI.
- Do not optimize painter code just because the loops look expensive in isolation.
- Do not treat build counters as a substitute for real paint/raster traces.
- Do not compare before/after numbers across different devices.
- Keep readability-only cleanup such as replacing `3.14159` with `pi` secondary unless nearby code is already being changed for a measured optimization.
